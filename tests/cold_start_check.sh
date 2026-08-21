#!/usr/bin/env bash
# 冷启动回归检查（issue #8）
#
# 把工作区拷到临时目录，在**没有可用全局类缓存**的前提下启动项目和测试。
# 任何 class_name 只要被引用而没有显式 preload，这里就会红。
#
#   bash tests/cold_start_check.sh
#
# 之所以是 shell 而不是 Godot 场景：要测的正是"Godot 还没加载好项目"这个阶段，
# 项目内部没法测自己。

set -u
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAILED=0
BAD_PATTERN="Parse Error|Compile Error|Failed to load script|Failed to instantiate an autoload|Nonexistent function|on a base object of type 'Nil'"

# 只拷源文件，刻意不拷 .godot/（模拟干净检出）
copy_sources() {
	if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
		git -C "$PROJECT_DIR" ls-files -z --cached --others --exclude-standard \
			| while IFS= read -r -d '' f; do
				case "$f" in .godot/*) continue ;; esac
				[ -f "$PROJECT_DIR/$f" ] || continue
				mkdir -p "$TMP_DIR/$(dirname "$f")"
				cp "$PROJECT_DIR/$f" "$TMP_DIR/$f"
			done
	else
		(cd "$PROJECT_DIR" && tar --exclude=.godot --exclude=.git -cf - .) \
			| (cd "$TMP_DIR" && tar -xf -)
	fi
}

run_phase() {
	local label="$1"; shift
	local output status bad
	output="$("$GODOT" --headless --path "$TMP_DIR" "$@" 2>&1)"
	status=$?
	bad="$(printf '%s\n' "$output" | grep -E "$BAD_PATTERN" || true)"
	if [ -n "$bad" ] || [ $status -ne 0 ]; then
		echo "  FAIL  $label"
		printf '%s\n' "${bad:-$output}" | head -12
		FAILED=1
	else
		echo "  PASS  $label"
	fi
}

echo "冷启动检查：$PROJECT_DIR → $TMP_DIR"
copy_sources
[ -d "$TMP_DIR/.godot" ] && { echo "失败：临时目录里不该有 .godot/"; exit 1; }

# 一次性构建步骤：把 PNG 之类的二进制素材导入成引擎格式。
# 这一步是 Godot 资源流水线的固有要求（跟 npm install 同性质），
# 有美术素材之后无法省略；它是可脚本化的命令，不需要打开编辑器。
echo
echo "[0] 首次导入素材（godot --import）"
if ! "$GODOT" --headless --path "$TMP_DIR" --import >/dev/null 2>&1; then
	echo "  FAIL  导入失败"
	exit 1
fi
echo "  PASS  导入完成"

echo
echo "[1] 导入后直接启动"
run_phase "启动游戏" --quit-after 60

# 真正要守的是这条：全局类缓存不可信。
# 干净检出、或者别人 pull 到含新 class_name 的代码而没重新导入，
# 缓存就是缺的/过期的 —— issue #8 报的正是这种。纹理保留、只把类表干掉。
echo
echo "[2] 类缓存缺失（纹理已导入）—— issue #8 的场景"
rm -f "$TMP_DIR/.godot/global_script_class_cache.cfg"
run_phase "启动游戏" --quit-after 60
run_phase "冒烟测试" res://tests/smoke_test.tscn
run_phase "流程状态测试" res://tests/run_flow_test.tscn
run_phase "生成测试" res://tests/generation_test.tscn
run_phase "模板块测试" res://tests/chunk_test.tscn
run_phase "回归测试" res://tests/regression_test.tscn

echo
if [ $FAILED -ne 0 ]; then
	echo "冷启动检查失败 —— 多半是某个 class_name 被引用但没有显式 preload，见 issue #8。"
	exit 1
fi
echo "冷启动检查全部通过"
