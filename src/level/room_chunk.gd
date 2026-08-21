class_name RoomChunk
extends RefCounted
## 一块**手绘**的房间模板，从 `assets/levels/chunks/*.room` 读进来。
##
## 为什么是纯文本而不是编辑器里的 TileMap 场景：
##   - 这个项目已经有一整套 JumpModel + BFS 可达性校验。文本格式能让
##     `chunk_test` 把你画的每一块跑一遍，直接在终端指出哪个平台跳不上去。
##   - 一个字符一格，diff 看得懂，改一格就是改一个字符。
##   - 不需要瓦片集就能开始画，美术还没到位也不挡路。
##
## 文件长这样（`---` 之前是头部，之后是网格）：
##
##     name: 断桥
##     tags: combat
##     depth: 2-
##     weight: 1.5
##     ---
##     ########################
##     #......................#
##     ...
##
## 图例见 LEGEND。整块必须是 CHUNK_ROWS 行；宽度自由，拼接只有横向一个自由度。

## 必须等于 LevelGrid.H。这里不 preload LevelGrid 是为了避免循环依赖
## （LevelGrid 要 preload 本文件），chunk_test 会断言两者一致。
const CHUNK_ROWS := 24
const MIN_COLS := 8
const MAX_COLS := 48

const SOLID := "#"      ## 实心地形
const EMPTY := "."      ## 空气
const ENTRY := "<"      ## 左接口落脚点，必须在第一列
const EXIT := ">"       ## 右接口落脚点，必须在最后一列
const GRUNT := "n"      ## 小兵刷点（这一格是空气）
const BRUTE := "N"      ## 精英刷点（这一格是空气）

const LEGEND := {
	SOLID: "实心地形",
	EMPTY: "空气",
	ENTRY: "左接口落脚点（必须且只能有一个，在第一列）",
	EXIT: "右接口落脚点（必须且只能有一个，在最后一列）",
	GRUNT: "小兵刷点",
	BRUTE: "精英刷点",
}

## 玩家站立需要几格净空（对应 LevelGrid.BODY_TILES）
const BODY_TILES := 2

var source_path := ""
var display_name := ""
var tags: PackedStringArray = PackedStringArray()
var weight := 1.0
var depth_min := 0
var depth_max := 9999

var width := 0
var solid: Array[PackedByteArray] = []
var entry := Vector2i(-1, -1)
var exit_cell := Vector2i(-1, -1)
var spawns: Array[Vector2i] = []         ## 小兵刷点
var elite_spawns: Array[Vector2i] = []   ## 精英刷点

## 解析/结构校验的报错。非空就说明这块不能用。
var errors: PackedStringArray = PackedStringArray()


# ---------------------------------------------------------------- 解析

## 从 .room 文本填充自己。读盘、挑块这些事在 chunk_library.gd 里 ——
## 本文件刻意不写任何静态工厂：那需要在自己内部引用 `RoomChunk`，
## 而那个名字要查 .godot/ 里的全局类缓存，干净检出时还不存在（issue #8）。
func load_from_text(text: String, path: String = "") -> void:
	source_path = path
	display_name = path.get_file().get_basename()

	var body := text.replace("\r\n", "\n")
	var split := body.split("\n---", true, 1)
	if split.size() != 2:
		errors.append("缺少 `---` 分隔线，头部和网格分不开")
		return

	_parse_header(split[0])
	_parse_grid(split[1])
	if errors.is_empty():
		_validate_shape()


func _parse_header(header: String) -> void:
	for raw_line in header.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var colon := line.find(":")
		if colon < 0:
			errors.append("头部这行没有冒号：`%s`" % line)
			continue
		var key := line.substr(0, colon).strip_edges().to_lower()
		var value := line.substr(colon + 1).strip_edges()
		match key:
			"name":
				display_name = value
			"tags":
				tags = PackedStringArray()
				for t in value.split(",", false):
					var tag := t.strip_edges()
					if not tag.is_empty():
						tags.append(tag)
			"weight":
				weight = maxf(value.to_float(), 0.0)
			"depth":
				_parse_depth(value)
			_:
				errors.append("头部有不认识的字段：`%s`" % key)


## `depth: 3` 只在第 3 层 / `depth: 2-5` 区间 / `depth: 2-` 从第 2 层起
func _parse_depth(value: String) -> void:
	var dash := value.find("-")
	if dash < 0:
		depth_min = value.to_int()
		depth_max = depth_min
		return
	var lo := value.substr(0, dash).strip_edges()
	var hi := value.substr(dash + 1).strip_edges()
	depth_min = lo.to_int() if not lo.is_empty() else 0
	depth_max = hi.to_int() if not hi.is_empty() else 9999
	if depth_max < depth_min:
		errors.append("depth 区间反了：%d-%d" % [depth_min, depth_max])


func _parse_grid(grid_text: String) -> void:
	var rows: Array[String] = []
	for raw_line in grid_text.split("\n"):
		# 行尾空白会让"每行等长"变成玄学，统一右裁；行内的空格是非法字符，会被下面查出来
		var line := raw_line.rstrip(" \t")
		if line.is_empty() and rows.is_empty():
			continue          # 分隔线后面的空行
		rows.append(line)
	while not rows.is_empty() and rows[rows.size() - 1].is_empty():
		rows.resize(rows.size() - 1)

	if rows.size() != CHUNK_ROWS:
		errors.append("要 %d 行，实际 %d 行" % [CHUNK_ROWS, rows.size()])
		return

	width = rows[0].length()
	if width < MIN_COLS or width > MAX_COLS:
		errors.append("宽度 %d 不在 %d~%d 之间" % [width, MIN_COLS, MAX_COLS])
		return
	for y in rows.size():
		if rows[y].length() != width:
			errors.append("第 %d 行宽度 %d，和第 1 行的 %d 不一致"
				% [y + 1, rows[y].length(), width])
			return

	solid = []
	for x in width:
		var col := PackedByteArray()
		col.resize(CHUNK_ROWS)
		solid.append(col)

	for y in CHUNK_ROWS:
		for x in width:
			var ch := rows[y][x]
			var cell := Vector2i(x, y)
			match ch:
				SOLID:
					solid[x][y] = 1
				EMPTY:
					pass
				ENTRY:
					if entry.x >= 0:
						errors.append("出现了不止一个 `%s`" % ENTRY)
					entry = cell
				EXIT:
					if exit_cell.x >= 0:
						errors.append("出现了不止一个 `%s`" % EXIT)
					exit_cell = cell
				GRUNT:
					spawns.append(cell)
				BRUTE:
					elite_spawns.append(cell)
				_:
					errors.append("第 %d 行第 %d 列是不认识的字符 `%s`"
						% [y + 1, x + 1, ch])
					return


# ---------------------------------------------------------------- 结构校验

## 只查"这块自己是不是画对了"，不查可达性 —— 那要 JumpModel，交给 chunk_test。
func _validate_shape() -> void:
	if entry.x < 0:
		errors.append("没有标 `%s`（左接口落脚点）" % ENTRY)
	elif entry.x != 0:
		errors.append("`%s` 必须在第一列，现在在第 %d 列" % [ENTRY, entry.x + 1])
	if exit_cell.x < 0:
		errors.append("没有标 `%s`（右接口落脚点）" % EXIT)
	elif exit_cell.x != width - 1:
		errors.append("`%s` 必须在最后一列（第 %d 列），现在在第 %d 列"
			% [EXIT, width, exit_cell.x + 1])

	# 上下必须封死，否则玩家会从房间外面掉出世界
	for x in width:
		if solid[x][0] == 0:
			errors.append("第 1 行第 %d 列不是 `%s` —— 顶部必须整行封死" % [x + 1, SOLID])
			break
	for x in width:
		if solid[x][CHUNK_ROWS - 1] == 0:
			errors.append("第 %d 行第 %d 列不是 `%s` —— 底部必须整行封死"
				% [CHUNK_ROWS, x + 1, SOLID])
			break

	for cell in _all_markers():
		if not is_standable(cell.x, cell.y):
			errors.append("(%d, %d) 站不住人：脚下要是实心，自己和头顶那格要是空的"
				% [cell.x + 1, cell.y + 1])


func _all_markers() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if entry.x >= 0:
		out.append(entry)
	if exit_cell.x >= 0:
		out.append(exit_cell)
	out.append_array(spawns)
	out.append_array(elite_spawns)
	return out


## 所有需要"人站得住"的标记点，chunk_test 拿它逐个查可达性
func markers() -> Array[Vector2i]:
	return _all_markers()


func is_free(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < CHUNK_ROWS and solid[x][y] == 0


## 和 LevelGrid.is_standable 同一套判据
func is_standable(x: int, y: int) -> bool:
	if y + 1 >= CHUNK_ROWS or not is_free(x, y):
		return false
	if solid[x][y + 1] == 0:
		return false
	for i in range(1, BODY_TILES):
		if not is_free(x, y - i):
			return false
	return true


# ---------------------------------------------------------------- 输出

## 把这一块画回 ASCII。`marks` 是额外的覆盖字符（比如把够不着的落脚点标成 `?`），
## 校验失败时打出来，作者一眼就能看到问题在哪一格。
func to_ascii(marks: Dictionary = {}) -> String:
	var lines: Array[String] = []
	for y in CHUNK_ROWS:
		var line := ""
		for x in width:
			var cell := Vector2i(x, y)
			if marks.has(cell):
				line += String(marks[cell])
			elif cell == entry:
				line += ENTRY
			elif cell == exit_cell:
				line += EXIT
			elif cell in elite_spawns:
				line += BRUTE
			elif cell in spawns:
				line += GRUNT
			else:
				line += SOLID if solid[x][y] == 1 else EMPTY
		lines.append("%2d %s" % [y + 1, line])
	return "\n".join(lines)
