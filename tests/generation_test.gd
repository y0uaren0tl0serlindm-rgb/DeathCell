extends Node
## 关卡生成校验：跑一大批 seed × 深度，逐个验证房间可通行。
##   godot --headless --path . res://tests/generation_test.tscn
##
## 对应 issue #1：程序化地形偶发生成不可通行路线。
## 这个测试不进场景树、不实例化角色，所以几百个房间只要几秒。

const SEED_COUNT := 300
const DEPTHS := [0, 1, 3, 5, 9, 15]

var _failures: Array[String] = []


func _ready() -> void:
	var total := 0
	var repaired := 0
	var worst_headroom := 99
	var min_reach_ratio := 1.0
	var platform_tiles := 0

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

			# 5. 顺带看看关卡的连通程度（太低说明地形碎得没法玩）
			var ratio := _reachable_ratio(grid)
			min_reach_ratio = minf(min_reach_ratio, ratio)

			platform_tiles += _platform_tile_count(grid)

	print("\n生成房间 %d 个（%d 个 seed × %d 种深度）" % [total, SEED_COUNT, DEPTHS.size()])
	print("  触发修复：%d 个" % repaired)
	print("  最差地面净空：%d 格（要求 ≥ %d）" % [worst_headroom, LevelGrid.BODY_TILES])
	print("  最低落脚点连通率：%.0f%%" % (min_reach_ratio * 100.0))
	var avg_platform := float(platform_tiles) / float(total)
	print("  平均悬空平台格数：%.1f" % avg_platform)

	# 关卡不能因为加约束就被约束没了：平台是战斗立体度的来源
	if avg_platform < 20.0:
		_fail("悬空平台平均只剩 %.1f 格，关卡太空旷" % avg_platform)

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


## 地面/洞顶之外的实心格 = 悬空平台
func _platform_tile_count(grid: LevelGrid) -> int:
	var n := 0
	for x in range(2, LevelGrid.W - 2):
		for y in range(grid.roof_row[x] + 1, grid.ground_row[x]):
			if grid.solid[x][y] == 1:
				n += 1
	return n


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
