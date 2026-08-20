extends Node
## 关卡生成校验：跑一大批 seed × 深度，逐个验证房间可通行。
##   godot --headless --path . res://tests/generation_test.tscn
##
## 两个生成器都要过同一组硬指标，各自还有自己的质量指标：
##   高度图   —— 地面走廊 + 悬空平台，看平台密度、地面净空、落差
##   智能体   —— 从入口用真实动作挖到出口的洞穴，看空腔占比、纵向跨度
##
## 对应 issue #1：程序化地形偶发生成不可通行路线。
## 不进场景树、不实例化角色，所以几百个房间只要几秒。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const LevelGrid = preload("res://src/level/level_grid.gd")
const JumpModel = preload("res://src/level/jump_model.gd")

const SEED_COUNT := 50
const DEPTHS := [0, 1, 3, 5, 9, 15]

## 落脚点连通率下限，两个生成器要求不同。
##
## 高度图要满分：那里够不着的是**悬空平台**，玩家看得见却站不上去，
## 正是 issue #7 抱怨的东西。
##
## 智能体洞穴放宽到 97%：剩下的是岩层内部一两格的凹槽 —— 玩家看不见也用不到，
## 而且实测这些空格往往是别的跳跃轨迹的必经通道，填掉反而会断路
## （_seal_unreachable_footholds 会逐个尝试并在弄坏时回滚）。
## 硬要清零就得改动挖掘算法本身，性价比不高。
const MIN_REACH_RATIO := 1.0
const MIN_REACH_RATIO_AGENT := 0.97

var _failures: Array[String] = []


func _ready() -> void:
	_check_constant_invariants()

	var heightmap := _run_suite(false, "高度图")
	var agent := _run_suite(true, "智能体挖掘")
	_print_comparison(heightmap, agent)

	LevelGrid.use_agent_carver = true   # 跑完恢复默认

	if _failures.is_empty():
		print("\n两个生成器的房间全部可通行")
		get_tree().quit(0)
	else:
		print("\n失败 %d 项，前 10 条：" % _failures.size())
		for f in _failures.slice(0, 10):
			print("  ", f)
		get_tree().quit(1)


func _run_suite(use_agent: bool, label: String) -> Dictionary:
	LevelGrid.use_agent_carver = use_agent
	var stats := {
		"label": label, "total": 0, "repaired": 0,
		"worst_headroom": 99, "worst_step": 0,
		"min_reach": 1.0, "platform_tiles": 0, "pruned": 0,
		"open_ratio": 0.0, "span": 0, "worst_span": 99, "msec": 0,
	}
	var t0 := Time.get_ticks_msec()

	for depth in DEPTHS:
		for s in SEED_COUNT:
			stats.total += 1
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("seed_%d_depth_%d" % [s, depth])
			var grid := LevelGrid.new()
			grid.build(rng)

			if grid.repairs > 0:
				stats.repaired += 1
			stats.pruned += grid.pruned_platforms

			# --- 两个生成器都必须满足的硬指标 ---
			if not grid.exit_reachable():
				_fail("%s seed=%d depth=%d 出口不可达" % [label, s, depth])
			var entry: Vector2i = grid.entrance_cell
			if not grid.is_standable(entry.x, entry.y):
				_fail("%s seed=%d depth=%d 入口站不住" % [label, s, depth])
			# 指标全部在一次全图扫描里算出来 —— 分开算的话每个房间要扫四遍
			var m: Dictionary = _measure(grid)
			stats.min_reach = minf(stats.min_reach, m.reach_ratio)
			var floor_ratio := MIN_REACH_RATIO_AGENT if use_agent else MIN_REACH_RATIO
			if m.reach_ratio < floor_ratio:
				_fail("%s seed=%d depth=%d 落脚点连通率只有 %.0f%%"
					% [label, s, depth, m.reach_ratio * 100.0])

			if use_agent:
				stats.open_ratio += m.open_ratio
				stats.span += m.span
				stats.worst_span = mini(stats.worst_span, m.span)
			else:
				var stranded := grid.unreachable_platform_count()
				if stranded > 0:
					_fail("%s seed=%d depth=%d 有 %d 块平台够不着" % [label, s, depth, stranded])
				stats.platform_tiles += grid.playable_platform_tile_count()
				var h: int = _min_ground_headroom(grid)
				stats.worst_headroom = mini(stats.worst_headroom, h)
				if h < LevelGrid.BODY_TILES:
					_fail("%s seed=%d depth=%d 地面净空只有 %d 格" % [label, s, depth, h])
				var step: int = _max_ground_step(grid)
				stats.worst_step = maxi(stats.worst_step, step)
				if step > JumpModel.comfortable_rise():
					_fail("%s seed=%d depth=%d 地面落差 %d 格超过跳跃能力" % [label, s, depth, step])

	stats.msec = Time.get_ticks_msec() - t0
	return stats


func _print_comparison(a: Dictionary, b: Dictionary) -> void:
	print("\n每个生成器 %d 个房间（%d seed × %d 深度）\n" % [a.total, SEED_COUNT, DEPTHS.size()])
	print("  %-22s %-16s %-16s" % ["指标", a.label, b.label])
	print("  " + "-".repeat(56))
	_row("落脚点连通率", "%.0f%%" % (a.min_reach * 100.0), "%.0f%%" % (b.min_reach * 100.0))
	_row("触发修复", "%d" % a.repaired, "%d" % b.repaired)
	_row("平均可玩平台", "%.1f 格" % (float(a.platform_tiles) / float(a.total)), "—（洞穴无平台）")
	_row("剪掉的够不着平台", "%d" % a.pruned, "%d" % b.pruned)
	_row("最差地面净空", "%d 格" % a.worst_headroom, "—")
	_row("最大地面落差", "%d 格" % a.worst_step, "—")
	_row("空腔占比", "—", "%.0f%%" % (float(b.open_ratio) / float(b.total) * 100.0))
	_row("可达区纵向跨度", "—", "%.1f 格（最小 %d）" % [float(b.span) / float(b.total), b.worst_span])
	_row("生成耗时", "%.1f ms/房间" % (float(a.msec) / float(a.total)), "%.1f ms/房间" % (float(b.msec) / float(b.total)))

	# 智能体版本不能退化成一条平走廊 —— 那这次改动就白做了
	var avg_span: float = float(b.span) / float(b.total)
	if avg_span < 6.0:
		_fail("智能体关卡纵向跨度平均只有 %.1f 格，和走廊没区别" % avg_span)
	var avg_open: float = float(b.open_ratio) / float(b.total)
	if avg_open < 0.12:
		_fail("智能体关卡空腔只占 %.0f%%，太逼仄" % (avg_open * 100.0))
	# 高度图那边的平台密度也不能因为改动而退化
	var avg_platform: float = float(a.platform_tiles) / float(a.total)
	if avg_platform < 35.0:
		_fail("高度图可玩平台平均只剩 %.1f 格，关卡太空旷" % avg_platform)


func _row(name: String, va: String, vb: String) -> void:
	print("  %-22s %-16s %-16s" % [name, va, vb])


func _fail(msg: String) -> void:
	_failures.append(msg)


## 常量之间的硬约束。这些值分散在两个文件里，很容易只改一个就破坏配合。
func _check_constant_invariants() -> void:
	# 平台落脚点比下方落脚点高 PLATFORM_CLEARANCE + 1 格，要跳得上去就不能超过实测跳跃高度。
	# 之前净空写 3、跳跃也写 3，平台永远比跳跃能力高一格，画得出来站不上去（issue #7）。
	# 现在跳跃高度是模拟出来的，改 player.gd 的跳跃参数这条断言会自动跟着变。
	var rise: int = JumpModel.comfortable_rise()
	var platform_rise: int = LevelGrid.PLATFORM_CLEARANCE + 1
	print("跳跃包络：最高 %d 格 / 稳妥 %d 格 / 平跳最远 %d 格"
		% [JumpModel.max_rise(), rise, JumpModel.max_run()])
	if platform_rise > rise:
		_fail("平台净空 %d 对应落脚点高差 %d 格，超过实测跳跃高度 %d 格"
			% [LevelGrid.PLATFORM_CLEARANCE, platform_rise, rise])
	if LevelGrid.PLATFORM_CLEARANCE < LevelGrid.BODY_TILES:
		_fail("平台净空 %d 格装不下 %d 格高的玩家"
			% [LevelGrid.PLATFORM_CLEARANCE, LevelGrid.BODY_TILES])


# ---------------------------------------------------------------- 指标

## 地面走廊上方最少留了几格空
func _min_ground_headroom(grid: LevelGrid) -> int:
	var worst := 99
	for x in range(2, LevelGrid.W - 2):
		var free_rows := 0
		var y := grid.ground_row[x] - 1
		while y > 0 and grid.is_free(x, y):
			free_rows += 1
			y -= 1
			if free_rows >= 9:
				break
		worst = mini(worst, free_rows)
	return worst


func _max_ground_step(grid: LevelGrid) -> int:
	var worst := 0
	for x in range(3, LevelGrid.W - 3):
		worst = maxi(worst, absi(grid.ground_row[x] - grid.ground_row[x - 1]))
	return worst


## 一次扫完全图，把所有指标算出来
func _measure(grid: LevelGrid) -> Dictionary:
	var reach := grid.reachable_cells()
	var standable := 0
	var free_cells := 0
	for x in LevelGrid.W:
		for y in LevelGrid.H:
			if grid.solid[x][y] == 0:
				free_cells += 1
				if grid.is_standable(x, y):
					standable += 1
	var top := 999
	var bottom := -1
	for cell in reach:
		var c: Vector2i = cell
		top = mini(top, c.y)
		bottom = maxi(bottom, c.y)
	return {
		"reach_ratio": float(reach.size()) / float(maxi(standable, 1)),
		"open_ratio": float(free_cells) / float(LevelGrid.W * LevelGrid.H),
		"span": maxi(bottom - top, 0) if bottom >= 0 else 0,
	}
