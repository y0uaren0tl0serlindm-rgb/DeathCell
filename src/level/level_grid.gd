class_name LevelGrid
extends RefCounted
## 房间的网格地形：生成 + 可达性校验 + 修复。
## 刻意不继承 Node —— 这样可以脱离场景树跑几百个种子做验证（见 tests/generation_test.gd）。
##
## 核心保证：**任何 seed、任何深度生成的房间，玩家都能从入口走到出口。**
## 做法是两层：
##   1. 按构造：地面走廊上方永远留够净空，落差不超过跳跃能力 —— 让不可通行根本生成不出来
##   2. 按校验：生成完做一次可达性搜索，万一还是断了就拆平台、再不行就铲平走廊
## 光靠第 1 层是不够的，随机生成里"我以为约束住了"和"真的约束住了"是两回事。

const TILE := 16
const W := 92
const H := 24

# --- 地形形状 ---
const MAX_STEP := 2          ## 相邻地面的最大高度差（格）
const MIN_LEDGE_RUN := 4     ## 一段平地至少多宽
const MIN_GROUND_ROW := 13
const MAX_GROUND_ROW := H - 3
const MAX_ROOF_ROW := 5
const ROOF_CLEARANCE := 6    ## 洞顶与地面之间至少留几格

# --- 玩家能力（必须和 player.gd 对齐；改跳跃参数要回来同步）---
## 玩家碰撞体 22px，一格 16px → 站立需要 2 格净空
const BODY_TILES := 2
## 平台底面与地面之间要留的净空，保证地面走廊永远走得过去。
## 它和 JUMP_UP 是耦合的，改一个必须回头看另一个：
## 净空 c 格 → 平台落脚点比地面落脚点高 c+1 格 → 想跳得上去必须 c + 1 <= JUMP_UP。
## 之前这里写 3，算出来平台永远高 4 格，比 JUMP_UP 还高一格，
## 于是平台画得出来、站不上去（issue #7）。
const PLATFORM_CLEARANCE := BODY_TILES
## 实测跳跃高度 52px ≈ 3.25 格，保守取 3
const JUMP_UP := 3

var solid: Array[PackedByteArray] = []
var ground_row: PackedInt32Array = PackedInt32Array()
var roof_row: PackedInt32Array = PackedInt32Array()
## 每列的"走廊禁区上沿"：这一行到地面之间必须保持畅通，否则玩家跨不过台阶。
## 只算净空是不够的 —— 玩家跳上台阶时头顶还要占掉几格，平台压在这里就会封路。
var corridor_ceiling: PackedInt32Array = PackedInt32Array()

var entrance_x := 4
var exit_x := W - 6

## 生成时做了几次修复。正常应该恒为 0；测试会盯着这个值。
var repairs := 0
## 因为够不着而被拆掉的平台块数
var pruned_platforms := 0

var _rng: RandomNumberGenerator
var _terrain_snapshot: Array[PackedByteArray] = []


func build(rng: RandomNumberGenerator) -> void:
	_rng = rng
	repairs = 0
	pruned_platforms = 0
	_build_heightmap()
	_compute_corridor_ceiling()
	_snapshot_terrain()
	_carve_platforms()
	_prune_unreachable_platforms()

	# 兜底：平台是可选内容，挡路了就整批拆掉
	if not exit_reachable():
		repairs += 1
		_restore_terrain()
	# 还不通说明地面本身有问题，铲出一条平走廊
	if not exit_reachable():
		repairs += 1
		_flatten_whole_corridor()


# ---------------------------------------------------------------- 生成

func _build_heightmap() -> void:
	solid.clear()
	for x in W:
		var col := PackedByteArray()
		col.resize(H)
		solid.append(col)

	ground_row = PackedInt32Array()
	ground_row.resize(W)
	roof_row = PackedInt32Array()
	roof_row.resize(W)

	var g := MAX_GROUND_ROW - 2
	var r := 2
	var since_step := 0
	for x in W:
		since_step += 1
		# 两次台阶之间至少隔 MIN_LEDGE_RUN 格，避免一格宽的锯齿地形
		if x > 6 and x < W - 8 and since_step >= MIN_LEDGE_RUN and _rng.randf() < 0.3:
			g = clampi(g + _rng.randi_range(-MAX_STEP, MAX_STEP), MIN_GROUND_ROW, MAX_GROUND_ROW)
			since_step = 0
		if _rng.randf() < 0.2:
			r = clampi(r + _rng.randi_range(-1, 1), 1, MAX_ROOF_ROW)
		ground_row[x] = g
		roof_row[x] = mini(r, g - ROOF_CLEARANCE)
		for y in range(g, H):
			solid[x][y] = 1
		for y in range(0, roof_row[x] + 1):
			solid[x][y] = 1

	for y in H:
		solid[0][y] = 1
		solid[1][y] = 1
		solid[W - 1][y] = 1
		solid[W - 2][y] = 1

	# 出入口附近铲平，避免出生就卡在斜坡里
	for x in range(2, 7):
		_flatten_column(x, MAX_GROUND_ROW - 2)
	for x in range(W - 8, W - 2):
		_flatten_column(x, ground_row[W - 9])


func _flatten_column(x: int, row: int) -> void:
	row = clampi(row, MIN_GROUND_ROW, MAX_GROUND_ROW)
	ground_row[x] = row
	roof_row[x] = mini(roof_row[x], row - ROOF_CLEARANCE)
	for y in range(H):
		solid[x][y] = 1 if (y >= row or y <= roof_row[x]) else 0


## 算出每列必须保持畅通的高度。
## 玩家从 x 跳到相邻台阶时，会沿"竖直上升 → 水平 → 下落"占用到 apex 上方一格，
## 所以禁区上沿取自己和左右邻居里最高的那个落脚点，再往上留出身高。
func _compute_corridor_ceiling() -> void:
	corridor_ceiling = PackedInt32Array()
	corridor_ceiling.resize(W)
	for x in W:
		var apex := ground_row[x] - 1
		if x > 0:
			apex = mini(apex, ground_row[x - 1] - 1)
		if x < W - 1:
			apex = mini(apex, ground_row[x + 1] - 1)
		corridor_ceiling[x] = apex - (BODY_TILES - 1)


## 悬空平台：给战斗和走位加一层立体空间。
##
## 高度不是随便取的：平台**正下方是跳不上去的**（会顶到平台底面），
## 真实路线是在平台边上起跳、再落到台面。所以基准落脚点取紧挨平台左边那一列，
## 平台落脚点正好比它高 JUMP_UP 格。
func _carve_platforms() -> void:
	# 记录哪些列已经有平台。平台互相叠会造出"站得下但进不去"的夹层：
	# 上下相隔正好 BODY_TILES 时人塞得进去，但移动过去需要顶点有 BODY_TILES 格净空，
	# 正好被上层挡死。与其事后检测，不如一开始就不让它们叠。
	var occupied := PackedByteArray()
	occupied.resize(W)

	var placed: Array = []   # [x0, x1, tile_row]
	for i in _rng.randi_range(7, 12):
		var x0 := -1
		var x1 := -1
		for attempt in 6:
			var a := _rng.randi_range(6, W - 12)
			var b := mini(a + _rng.randi_range(3, 7), W - 2)
			# 左右各留一列空隙，起跳的那一列不能被别的平台占着
			if _span_free(occupied, a - 1, b + 1):
				x0 = a
				x1 = b
				break
		if x0 < 0:
			continue
		var support := ground_row[maxi(x0 - 1, 2)] - 1     # 边上那一列的落脚点
		var y := _place_platform(x0, x1, support - JUMP_UP + 1)
		if y > 0:
			placed.append([x0, x1, y])
			_mark_span(occupied, x0, x1)

	# 第二层：接在下层平台**右边**继续往上，摞成楼梯而不是夹层。
	# 压在下层头顶的话，下层就变成走不进去的死区（issue #7）。
	for p in placed:
		if _rng.randf() > 0.45:
			continue
		var a: int = p[1]                      # 紧接下层右缘，起跳点是下层最后一列
		var b: int = mini(a + _rng.randi_range(3, 5), W - 2)
		if b - a < 2 or not _span_free(occupied, a, b + 1):
			continue
		var support2: int = p[2] - 1           # 下层平台的落脚点
		var y2 := _place_platform(a, b, support2 - JUMP_UP + 1)
		if y2 > 0:
			_mark_span(occupied, a, b)


func _span_free(occupied: PackedByteArray, x0: int, x1: int) -> bool:
	for x in range(maxi(x0, 0), mini(x1, W)):
		if occupied[x] == 1:
			return false
	return true


func _mark_span(occupied: PackedByteArray, x0: int, x1: int) -> void:
	for x in range(maxi(x0, 0), mini(x1, W)):
		occupied[x] = 1


## 放一段平台，返回实际使用的砖块行；放不下返回 -1。
## 压到走廊禁区时整块抬高而不是丢弃 —— 直接丢会让关卡变空旷。
func _place_platform(x0: int, x1: int, desired: int) -> int:
	var limit := H
	for x in range(x0, x1):
		limit = mini(limit, corridor_ceiling[x] - 1)
		limit = mini(limit, ground_row[x] - 1 - PLATFORM_CLEARANCE)
	var y := mini(desired, limit)

	var any := false
	for x in range(x0, x1):
		if y >= corridor_ceiling[x] or y > ground_row[x] - 1 - PLATFORM_CLEARANCE:
			continue
		if y <= roof_row[x] + BODY_TILES:
			continue   # 贴着洞顶的平台站不上去，别放
		solid[x][y] = 1
		any = true
		# 平台上方留出通行高度
		for dy in range(1, BODY_TILES + 2):
			if y - dy > roof_row[x]:
				solid[x][y - dy] = 0
	return y if any else -1


## 把没有任何可达落脚点的平台整块拆掉。
## 按构造摆放已经能让绝大多数平台可达，但"我以为够得着"和"真的够得着"是两回事，
## 所以仍然用可达性搜索兜一道。拆掉一块可能让另一块失去踏脚点，所以要迭代。
func _prune_unreachable_platforms() -> void:
	for attempt in 4:
		var reach := reachable_cells()
		var removed := false
		for comp in platform_components():
			if _component_reachable(comp, reach):
				continue
			for cell in comp:
				solid[cell.x][cell.y] = 0
			removed = true
			pruned_platforms += 1
		if not removed:
			return


func _component_reachable(comp: Array, reach: Dictionary) -> bool:
	for cell in comp:
		if reach.has(Vector2i(cell.x, cell.y - 1)):
			return true
	return false


## 悬空平台的砖块（地形之外后来加上去的那些）
func is_platform_tile(x: int, y: int) -> bool:
	if x < 0 or x >= W or y < 0 or y >= H or solid[x][y] == 0:
		return false
	return _terrain_snapshot.size() == W and _terrain_snapshot[x][y] == 0


## 把相连的平台砖块分组，一组就是玩家眼里的"一块平台"
func platform_components() -> Array:
	const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var seen := {}
	var comps := []
	for x in W:
		for y in H:
			if not is_platform_tile(x, y):
				continue
			var key := Vector2i(x, y)
			if seen.has(key):
				continue
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [key]
			seen[key] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				comp.append(c)
				for d in NEIGHBORS:
					var n: Vector2i = c + d
					if is_platform_tile(n.x, n.y) and not seen.has(n):
						seen[n] = true
						stack.append(n)
			comps.append(comp)
	return comps


## 有可达落脚点的平台砖块数。只有这些才算真正的"可玩平台"，
## 装饰性的够不着的平台不该计进关卡立体度指标（issue #7）。
func playable_platform_tile_count() -> int:
	var reach := reachable_cells()
	var n := 0
	for comp in platform_components():
		if _component_reachable(comp, reach):
			n += comp.size()
	return n


## 够不着的平台组件数量。正常应该恒为 0。
func unreachable_platform_count() -> int:
	var reach := reachable_cells()
	var n := 0
	for comp in platform_components():
		if not _component_reachable(comp, reach):
			n += 1
	return n


func _snapshot_terrain() -> void:
	_terrain_snapshot.clear()
	for x in W:
		_terrain_snapshot.append(solid[x].duplicate())


func _restore_terrain() -> void:
	for x in W:
		solid[x] = _terrain_snapshot[x].duplicate()


func _flatten_whole_corridor() -> void:
	for x in range(2, W - 2):
		_flatten_column(x, MAX_GROUND_ROW - 2)
	_snapshot_terrain()   # 地形变了，平台判定的基准也要跟着更新


# ---------------------------------------------------------------- 查询

func is_free(x: int, y: int) -> bool:
	return x >= 0 and x < W and y >= 0 and y < H and solid[x][y] == 0


## (x, y) 能不能站人：脚下是实心，自己和头顶那格是空的
func is_standable(x: int, y: int) -> bool:
	if y + 1 >= H or not is_free(x, y):
		return false
	if solid[x][y + 1] == 0:
		return false
	for i in range(1, BODY_TILES):
		if not is_free(x, y - i):
			return false
	return true


func foothold(x: int) -> Vector2i:
	return Vector2i(x, ground_row[x] - 1)


# ---------------------------------------------------------------- 可达性

## 跳跃能覆盖的水平距离随高度差衰减：往上跳得越高，能横move的越少。
## 全部取保守值 —— 宁可误判为"不可达"而重生成，也不能放过真的走不通的房间。
static func _max_dx(dy: int) -> int:
	if dy > 0:
		return 6     # 下落：滞空久，飘得远
	if dy >= -1:
		return 5
	if dy == -2:
		return 4
	return 3         # 跳满 3 格高时几乎只能垂直上


func _column_clear(x: int, y_top: int, y_bottom: int) -> bool:
	for y in range(y_top - (BODY_TILES - 1), y_bottom + 1):
		if not is_free(x, y):
			return false
	return true


func _row_clear(y: int, x_from: int, x_to: int) -> bool:
	for x in range(mini(x_from, x_to), maxi(x_from, x_to) + 1):
		for i in BODY_TILES:
			if not is_free(x, y - i):
				return false
	return true


## 用"竖直上升 → 水平移动 → 竖直下落"的 L 形路径近似跳跃轨迹。
## 比真实抛物线保守，够用且不会漏判。
func _can_move(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var dx := to_cell.x - from_cell.x
	var dy := to_cell.y - from_cell.y
	if dx == 0 and dy == 0:
		return false
	if dy < -JUMP_UP or absi(dx) > _max_dx(dy):
		return false
	var apex := mini(from_cell.y, to_cell.y)
	return _column_clear(from_cell.x, apex, from_cell.y) \
		and _row_clear(apex, from_cell.x, to_cell.x) \
		and _column_clear(to_cell.x, apex, to_cell.y)


## 从入口做一次 BFS，返回所有能站上去的格子
func reachable_cells() -> Dictionary:
	# 先把落脚点按列分桶，搜索时只看邻近几列
	var by_column: Array[Array] = []
	by_column.resize(W)
	for x in W:
		by_column[x] = []
	for x in W:
		for y in H:
			if is_standable(x, y):
				by_column[x].append(Vector2i(x, y))

	var start := foothold(entrance_x)
	var visited := {}
	if not is_standable(start.x, start.y):
		return visited

	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		var lo := maxi(cell.x - 6, 0)
		var hi := mini(cell.x + 6, W - 1)
		for x in range(lo, hi + 1):
			for target in by_column[x]:
				if visited.has(target):
					continue
				if _can_move(cell, target):
					visited[target] = true
					queue.append(target)
	return visited


func exit_reachable() -> bool:
	var goal := foothold(exit_x)
	if not is_standable(goal.x, goal.y):
		return false
	return reachable_cells().has(goal)


func world_size() -> Vector2:
	return Vector2(W * TILE, H * TILE)


func tile_to_world(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * TILE, y * TILE)
