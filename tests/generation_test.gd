extends Node
## 关卡生成校验：跑一大批 seed × 深度，逐个验证房间可通行。
##   godot --headless --path . res://tests/generation_test.tscn
##
## 对应 issue #1：程序化地形偶发生成不可通行路线。
## 这个测试不进场景树、不实例化角色，所以几百个房间只要几秒。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const LevelGrid = preload("res://src/level/level_grid.gd")

const SEED_COUNT := 300
const DEPTHS := [0, 1, 3, 5, 9, 15]
## 落脚点连通率下限。目前实测 1800 个房间全部是 100% —— 生成器不产出
## 任何够不着的落脚点，所以这里直接要求满分。
## 以后真要做"只能看不能站"的装饰平台，要先把它和可玩平台区分开再放宽这个值。
const MIN_REACH_RATIO := 1.0

var _failures: Array[String] = []


func _ready() -> void:
	_check_constant_invariants()

	var total := 0
	var repaired := 0
	var worst_headroom := 99
	var min_reach_ratio := 1.0
	var platform_tiles := 0
	var pruned := 0
	var unreachable_platforms := 0

	for depth in DEPTHS:
		for s in SEED_COUNT:
			total += 1
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("seed_%d_depth_%d" % [s, depth])

			var grid := LevelGrid.new()
			grid.build(rng)

			if grid.repairs > 0:
				repaired += 1

			# 1. 出口必须可达
			if not grid.exit_reachable():
				_fail("seed=%d depth=%d 出口不可达" % [s, depth])

			# 2. 出入口本身要站得住
			var entry := grid.foothold(grid.entrance_x)
			if not grid.is_standable(entry.x, entry.y):
				_fail("seed=%d depth=%d 入口站不住" % [s, depth])

			# 3. 地面走廊每一列都要留够玩家身高的净空
			var h := _min_ground_headroom(grid)
			worst_headroom = mini(worst_headroom, h)
			if h < LevelGrid.BODY_TILES:
				_fail("seed=%d depth=%d 地面净空只有 %d 格" % [s, depth, h])

			# 4. 相邻地面落差不能超过跳跃能力
			var step := _max_ground_step(grid)
			if step > LevelGrid.JUMP_UP:
				_fail("seed=%d depth=%d 地面落差 %d 格超过跳跃能力" % [s, depth, step])

			# 5. 每块悬空平台都必须有至少一个从入口可达的落脚点（issue #7）
			var stranded := grid.unreachable_platform_count()
			unreachable_platforms += stranded
			if stranded > 0:
				_fail("seed=%d depth=%d 有 %d 块平台够不着" % [s, depth, stranded])
			pruned += grid.pruned_platforms

			# 6. 落脚点连通率：这里要断言，不能只打印
			var ratio := _reachable_ratio(grid)
			min_reach_ratio = minf(min_reach_ratio, ratio)
			if ratio < MIN_REACH_RATIO:
				_fail("seed=%d depth=%d 落脚点连通率只有 %.0f%%" % [s, depth, ratio * 100.0])

			# 只统计真正站得上去的平台，装饰性的不算关卡立体度
			platform_tiles += grid.playable_platform_tile_count()

	print("\n生成房间 %d 个（%d 个 seed × %d 种深度）" % [total, SEED_COUNT, DEPTHS.size()])
	print("  触发修复：%d 个" % repaired)
	print("  最差地面净空：%d 格（要求 ≥ %d）" % [worst_headroom, LevelGrid.BODY_TILES])
	print("  最低落脚点连通率：%.0f%%（要求 ≥ %.0f%%）" % [min_reach_ratio * 100.0, MIN_REACH_RATIO * 100.0])
	print("  够不着的平台：%d 块（生成时已拆掉 %d 块）" % [unreachable_platforms, pruned])
	var avg_platform := float(platform_tiles) / float(total)
	print("  平均可玩平台格数：%.1f" % avg_platform)

	# 关卡不能因为加约束就被约束没了：平台是战斗立体度的来源
	if avg_platform < 35.0:
		_fail("可玩平台平均只剩 %.1f 格，关卡太空旷" % avg_platform)

	# 剪枝是兜底，不该是常态。拆得多说明摆放逻辑本身算错了高度，
	# 光看连通率是发现不了的 —— 拆干净之后连通率照样 100%（issue #7）。
	var prune_rate := float(pruned) / float(total)
	if prune_rate > 0.5:
		_fail("平均每个房间要拆掉 %.2f 块够不着的平台，摆放高度算错了" % prune_rate)

	if _failures.is_empty():
		print("\n全部房间可通行")
		get_tree().quit(0)
	else:
		print("\n失败 %d 项，前 10 条：" % _failures.size())
		for f in _failures.slice(0, 10):
			print("  ", f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


## 常量之间的硬约束。这些值分散在两个文件里，很容易只改一个就破坏配合。
func _check_constant_invariants() -> void:
	# 平台落脚点比下方落脚点高 PLATFORM_CLEARANCE + 1 格，要跳得上去就不能超过 JUMP_UP。
	# 之前净空写 3、跳跃写 3，平台永远比跳跃能力高一格，画得出来站不上去（issue #7）。
	var platform_rise: int = LevelGrid.PLATFORM_CLEARANCE + 1
	if platform_rise > LevelGrid.JUMP_UP:
		_fail("平台净空 %d 对应落脚点高差 %d 格，超过跳跃能力 %d 格"
			% [LevelGrid.PLATFORM_CLEARANCE, platform_rise, LevelGrid.JUMP_UP])
	# 净空至少要装得下玩家，否则走廊钻不过去
	if LevelGrid.PLATFORM_CLEARANCE < LevelGrid.BODY_TILES:
		_fail("平台净空 %d 格装不下 %d 格高的玩家"
			% [LevelGrid.PLATFORM_CLEARANCE, LevelGrid.BODY_TILES])


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


## 能站的格子里，有多少比例是从入口走得到的
func _reachable_ratio(grid: LevelGrid) -> float:
	var standable := 0
	for x in LevelGrid.W:
		for y in LevelGrid.H:
			if grid.is_standable(x, y):
				standable += 1
	if standable == 0:
		return 0.0
	return float(grid.reachable_cells().size()) / float(standable)
