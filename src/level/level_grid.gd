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

const JumpModel = preload("res://src/level/jump_model.gd")
const AgentCarver = preload("res://src/level/agent_carver.gd")
const RoomChunk = preload("res://src/level/room_chunk.gd")
const ChunkLibrary = preload("res://src/level/chunk_library.gd")

const TILE := 16
## 默认房间宽度。宽度是**实例变量** `width`，因为模板块生成器把若干张手绘的
## chunk 横向拼起来，最终宽度是各块之和、每次都不一样。
## 高度仍然是常量：所有 chunk 都是 H 行高，拼接只有横向一个自由度。
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
## 它和跳跃能力是耦合的：净空 c 格 → 平台落脚点比地面落脚点高 c+1 格 →
## 想跳得上去必须 c + 1 <= JumpModel.comfortable_rise()。
## 之前这里写 3、跳跃能力也是 3，平台永远比跳跃能力高一格，
## 画得出来站不上去（issue #7）。generation_test 会断言这条关系。
const PLATFORM_CLEARANCE := BODY_TILES

## 这个房间实际有多少列。build() 会按生成器的产出重设它。
var width := W

var solid: Array[PackedByteArray] = []
var ground_row: PackedInt32Array = PackedInt32Array()
var roof_row: PackedInt32Array = PackedInt32Array()
## 每列的"走廊禁区上沿"：这一行到地面之间必须保持畅通，否则玩家跨不过台阶。
## 只算净空是不够的 —— 玩家跳上台阶时头顶还要占掉几格，平台压在这里就会封路。
var corridor_ceiling: PackedInt32Array = PackedInt32Array()

var entrance_x := 4
var exit_x := W - 6
## 入口/出口的落脚点。高度图生成器从 ground_row 推出来，
## 智能体生成器直接给出 —— 洞穴里"每列的地面高度"这个概念本身就不成立。
var entrance_cell: Vector2i
var exit_cell: Vector2i

## 三个生成器：
##   HEIGHTMAP —— 地面随机游走 + 悬空平台，出来的是"一条走廊 + 挂件"
##   AGENT     —— 智能体从入口用真实动作挖到出口，出来的是洞穴
##   CHUNKS    —— 把 assets/levels/chunks 里手绘的模板块横向拼起来
## 做成静态变量是为了能 A/B 对比：关卡测试三个都跑一遍，对比指标。
enum Generator { HEIGHTMAP, AGENT, CHUNKS }

static var generator: Generator = Generator.CHUNKS

## 拼接后左右各封几列，免得玩家从模板块的边缘走出房间
const BORDER := 2
## 拼到多宽就够一层了。凑不成整数没关系，最后一块整块放进去。
const CHUNK_TARGET_COLS := 78

## 模板块作者亲手标出来的刷怪点：`[{cell: Vector2i, elite: bool}, ...]`。
## 只有 CHUNKS 生成器会填它 —— 另外两个生成器是程序化的，"这里该站个精英"
## 这种判断没人做过，只能由 spawn_footholds() 随机挑。
var authored_spawns: Array = []

## 这个房间是用哪个生成器实际造出来的。
## CHUNKS 拼不出通路时会退回 AGENT，所以它不一定等于 `generator`。
var used_generator: Generator = Generator.AGENT

## 生成时做了几次修复。正常应该恒为 0；测试会盯着这个值。
var repairs := 0
## 因为够不着而被拆掉的平台块数
var pruned_platforms := 0

var _rng: RandomNumberGenerator
var _terrain_snapshot: Array[PackedByteArray] = []
## 可达性搜索结果缓存。地形一改就作废 —— 生成过程里要反复查，
## 每次重跑 BFS 会让 1800 个房间的生成测试慢一个数量级。
var _reach_cache = null


func _invalidate_reach() -> void:
	_reach_cache = null


func build(rng: RandomNumberGenerator, depth: int = 0) -> void:
	_rng = rng
	repairs = 0
	pruned_platforms = 0
	authored_spawns = []
	width = W
	match generator:
		Generator.CHUNKS:
			_build_with_chunks(depth)
		Generator.HEIGHTMAP:
			used_generator = Generator.HEIGHTMAP
			_build_with_heightmap()
		_:
			used_generator = Generator.AGENT
			_build_with_agent()


# ---------------------------------------------------------------- 模板块拼接

## 把手绘的模板块横向接起来。
##
## 和另外两个生成器的关系：这里的关卡结构是**人定的**，程序只负责挑块、
## 验接缝、兜底。所以它是唯一一个可能"造不出来"的生成器 —— 块库为空、
## 或者手上的块凑不出一条通路时退回智能体挖掘，保证任何情况下都有关卡可玩。
##
## 接缝的判据和房间内部完全一样：从上一块的出口落脚点往右走一格到下一块的
## 入口落脚点，这一步必须是 JumpModel 里真实存在的移动。挑块时先用位移表
## 粗筛（便宜），拼完再整体跑一次 BFS 兜底（准确）。
func _build_with_chunks(depth: int) -> void:
	var pool := ChunkLibrary.for_depth(depth)
	if pool.is_empty():
		used_generator = Generator.AGENT
		_build_with_agent()
		return
	for attempt in 8:
		var seq := _pick_chunk_sequence(pool)
		if seq.is_empty():
			continue
		_assemble_chunks(seq)
		if exit_reachable():
			used_generator = Generator.CHUNKS
			return
		repairs += 1
	# 手上的块凑不出通路。别把关卡铲平，换个生成器还能玩。
	used_generator = Generator.AGENT
	_build_with_agent()


## 用指定的模板块序列直接拼，跳过随机挑块。校验工具和预览用。
##
## 刻意不做成 `static func from_chunks() -> LevelGrid` 那样的工厂：
## 那要在本文件里写出自己的 `class_name`，而那个名字得查
## `.godot/global_script_class_cache.cfg` —— 干净检出时缓存还不存在（issue #8）。
## 调用方 preload 了本脚本，自己 `new()` 一个再调这个方法就没这个问题。
func build_from_chunks(seq: Array) -> void:
	_rng = RandomNumberGenerator.new()
	repairs = 0
	pruned_platforms = 0
	_assemble_chunks(seq)
	used_generator = Generator.CHUNKS


func _pick_chunk_sequence(pool: Array) -> Array:
	var seq: Array = []
	var total := 0
	var prev: RoomChunk = null
	while total < CHUNK_TARGET_COLS:
		var candidates: Array = []
		for c in pool:
			var chunk: RoomChunk = c
			# 接缝：从 prev 的出口往右一格落到 chunk 的入口
			if prev != null and not JumpModel.can_reach(
					Vector2i(1, chunk.entry.y - prev.exit_cell.y)):
				continue
			# 尽量别连着用同一块 —— 两段一模一样的地形一眼就看出来是拼的
			if chunk == prev and pool.size() > 1:
				continue
			candidates.append(chunk)
		if candidates.is_empty():
			return []
		var picked := _weighted_pick(candidates)
		seq.append(picked)
		total += picked.width
		prev = picked
	return seq


func _weighted_pick(candidates: Array) -> RoomChunk:
	var total := 0.0
	for c in candidates:
		total += maxf((c as RoomChunk).weight, 0.0)
	if total <= 0.0:
		return candidates[_rng.randi() % candidates.size()]
	var roll := _rng.randf() * total
	for c in candidates:
		roll -= maxf((c as RoomChunk).weight, 0.0)
		if roll <= 0.0:
			return c
	return candidates[candidates.size() - 1]


func _assemble_chunks(seq: Array) -> void:
	_invalidate_reach()
	authored_spawns = []

	var inner := 0
	for c in seq:
		inner += (c as RoomChunk).width
	width = BORDER * 2 + inner

	# 先整块填实心，左右封边就自然有了；模板块再逐列覆盖进去
	solid = []
	for x in width:
		var col := PackedByteArray()
		col.resize(H)
		col.fill(1)
		solid.append(col)

	var ox := BORDER
	for i in seq.size():
		var c: RoomChunk = seq[i]
		for x in c.width:
			for y in H:
				solid[ox + x][y] = c.solid[x][y]
		for cell in c.spawns:
			authored_spawns.append({"cell": Vector2i(ox + cell.x, cell.y), "elite": false})
		for cell in c.elite_spawns:
			authored_spawns.append({"cell": Vector2i(ox + cell.x, cell.y), "elite": true})
		if i == 0:
			entrance_cell = Vector2i(ox + c.entry.x, c.entry.y)
		if i == seq.size() - 1:
			exit_cell = Vector2i(ox + c.exit_cell.x, c.exit_cell.y)
		ox += c.width

	entrance_x = entrance_cell.x
	exit_x = exit_cell.x
	# 模板块里没有"悬空平台"这个概念，整张图都是地形
	_snapshot_terrain()
	_invalidate_reach()


## 智能体挖掘：可达性是路径本身的性质，不需要事后推导约束
func _build_with_agent() -> void:
	# 挖出来的路偶尔会把自己堵死（智能体绕回自己挖开的区域）。
	# 与其把关卡铲平成一条直走廊，不如换个随机流重挖 —— 保住关卡质量。
	var base_exit := width - 6
	for attempt in 4:
		var rng := RandomNumberGenerator.new()
		rng.seed = _rng.randi()
		var carver := AgentCarver.new()
		carver.carve(width, H, rng, 4, base_exit)
		solid = carver.solid
		entrance_cell = carver.entrance_cell
		exit_cell = carver.exit_cell
		entrance_x = entrance_cell.x
		exit_x = exit_cell.x
		# 洞穴里没有"悬空平台"这个概念，整张图都是地形
		_snapshot_terrain()
		_invalidate_reach()
		if exit_reachable() and exit_cell.x >= base_exit - 6:
			_seal_unreachable_footholds()
			return
		repairs += 1
	# 四次都没挖通才铲直通道
	_dig_straight_corridor()


func _build_with_heightmap() -> void:
	_build_heightmap()
	_compute_corridor_ceiling()
	# 出入口必须在剪枝之前定下来：剪枝要跑可达性搜索，
	# 而搜索的起点就是 entrance_cell —— 晚一步设的话起点是 (0,0)，
	# 可达集直接为空，平台会被全部误判成够不着而拆光。
	entrance_cell = foothold(entrance_x)
	exit_cell = foothold(exit_x)
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


## 填掉玩家够不着的落脚点。
##
## 挖掘会在岩层里留下 1 格高的凹槽之类的角落：地是实的、人站得下，
## 但头顶被压住钻不进去 —— 正是 issue #7 抱怨的"看得见站不上去"。
##
## 填之前先记下可达集，填完要是反而变小了（说明那些空格是某条轨迹的必经通道）
## 就回滚。整批回滚会让一个有问题的格子连累其他本可以填的，
## 所以整批失败后再逐个试一遍。
func _seal_unreachable_footholds() -> void:
	for attempt in 3:
		var targets := _stranded_footholds()
		if targets.is_empty():
			return
		if _try_seal(targets):
			continue          # 填成功了，再看一轮有没有新暴露出来的
		# 整批不行，逐个来
		var sealed_any := false
		for c in targets:
			if _try_seal([c]):
				sealed_any = true
		if not sealed_any:
			return
	_snapshot_terrain()


func _stranded_footholds() -> Array[Vector2i]:
	var reach := reachable_cells()
	var out: Array[Vector2i] = []
	for x in width:
		for y in H:
			if is_standable(x, y) and not reach.has(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


## 填掉这些格子；如果反而弄断了原有的路就回滚，返回是否填成功
func _try_seal(cells: Array) -> bool:
	var before: int = reachable_cells().size()
	for c in cells:
		solid[c.x][c.y] = 1
	_invalidate_reach()
	if reachable_cells().size() < before:
		for c in cells:
			solid[c.x][c.y] = 0
		_invalidate_reach()
		return false
	return true


## 最后的兜底：从入口到出口横着挖一条直通道
func _dig_straight_corridor() -> void:
	_invalidate_reach()
	var y := entrance_cell.y
	for x in range(2, width - 2):
		for dy in range(0, BODY_TILES + 2):
			solid[x][y - dy] = 0
		solid[x][y + 1] = 1
	exit_cell = Vector2i(exit_x, y)
	_snapshot_terrain()


# ---------------------------------------------------------------- 生成

func _build_heightmap() -> void:
	_invalidate_reach()
	solid.clear()
	for x in width:
		var col := PackedByteArray()
		col.resize(H)
		solid.append(col)

	ground_row = PackedInt32Array()
	ground_row.resize(width)
	roof_row = PackedInt32Array()
	roof_row.resize(width)

	var g := MAX_GROUND_ROW - 2
	var r := 2
	var since_step := 0
	for x in width:
		since_step += 1
		# 两次台阶之间至少隔 MIN_LEDGE_RUN 格，避免一格宽的锯齿地形
		if x > 6 and x < width - 8 and since_step >= MIN_LEDGE_RUN and _rng.randf() < 0.3:
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
		solid[width - 1][y] = 1
		solid[width - 2][y] = 1

	# 出入口附近铲平，避免出生就卡在斜坡里
	for x in range(2, 7):
		_flatten_column(x, MAX_GROUND_ROW - 2)
	for x in range(width - 8, width - 2):
		_flatten_column(x, ground_row[width - 9])


func _flatten_column(x: int, row: int) -> void:
	_invalidate_reach()
	row = clampi(row, MIN_GROUND_ROW, MAX_GROUND_ROW)
	ground_row[x] = row
	roof_row[x] = mini(roof_row[x], row - ROOF_CLEARANCE)
	for y in range(H):
		solid[x][y] = 1 if (y >= row or y <= roof_row[x]) else 0


## 算出每列必须保持畅通的高度。
## 玩家跳上相邻台阶时头顶要占掉身高那么多格，所以禁区上沿取
## 自己和左右邻居里最高的那个落脚点，再往上留出身高。
func _compute_corridor_ceiling() -> void:
	corridor_ceiling = PackedInt32Array()
	corridor_ceiling.resize(width)
	for x in width:
		var apex := ground_row[x] - 1
		if x > 0:
			apex = mini(apex, ground_row[x - 1] - 1)
		if x < width - 1:
			apex = mini(apex, ground_row[x + 1] - 1)
		corridor_ceiling[x] = apex - (BODY_TILES - 1)


## 悬空平台：给战斗和走位加一层立体空间。
##
## 高度不是随便取的：平台**正下方是跳不上去的**（会顶到平台底面），
## 真实路线是在平台边上起跳、再落到台面。所以基准落脚点取紧挨平台左边那一列，
## 平台落脚点正好比它高 JumpModel.comfortable_rise() 格 —— 这个数字是模拟出来的，
## 不是手推的。
func _carve_platforms() -> void:
	# 记录哪些列已经有平台。平台互相叠会造出"站得下但进不去"的夹层：
	# 上下相隔正好 BODY_TILES 时人塞得进去，但移动过去需要顶点有 BODY_TILES 格净空，
	# 正好被上层挡死。与其事后检测，不如一开始就不让它们叠。
	var occupied := PackedByteArray()
	occupied.resize(width)

	var placed: Array = []   # [x0, x1, tile_row]
	for i in _rng.randi_range(7, 12):
		var x0 := -1
		var x1 := -1
		for attempt in 6:
			var a := _rng.randi_range(6, width - 12)
			var b := mini(a + _rng.randi_range(3, 7), width - 2)
			# 左右各留一列空隙，起跳的那一列不能被别的平台占着
			if _span_free(occupied, a - 1, b + 1):
				x0 = a
				x1 = b
				break
		if x0 < 0:
			continue
		var support := ground_row[maxi(x0 - 1, 2)] - 1     # 边上那一列的落脚点
		var y := _place_platform(x0, x1, support - JumpModel.comfortable_rise() + 1)
		if y > 0:
			placed.append([x0, x1, y])
			_mark_span(occupied, x0, x1)

	# 第二层：接在下层平台**右边**继续往上，摞成楼梯而不是夹层。
	# 压在下层头顶的话，下层就变成走不进去的死区（issue #7）。
	for p in placed:
		if _rng.randf() > 0.45:
			continue
		var a: int = p[1]                      # 紧接下层右缘，起跳点是下层最后一列
		var b: int = mini(a + _rng.randi_range(3, 5), width - 2)
		if b - a < 2 or not _span_free(occupied, a, b + 1):
			continue
		var support2: int = p[2] - 1           # 下层平台的落脚点
		var y2 := _place_platform(a, b, support2 - JumpModel.comfortable_rise() + 1)
		if y2 > 0:
			_mark_span(occupied, a, b)


func _span_free(occupied: PackedByteArray, x0: int, x1: int) -> bool:
	for x in range(maxi(x0, 0), mini(x1, width)):
		if occupied[x] == 1:
			return false
	return true


func _mark_span(occupied: PackedByteArray, x0: int, x1: int) -> void:
	for x in range(maxi(x0, 0), mini(x1, width)):
		occupied[x] = 1


## 放一段平台，返回实际使用的砖块行；放不下返回 -1。
## 压到走廊禁区时整块抬高而不是丢弃 —— 直接丢会让关卡变空旷。
func _place_platform(x0: int, x1: int, desired: int) -> int:
	_invalidate_reach()
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
	if x < 0 or x >= width or y < 0 or y >= H or solid[x][y] == 0:
		return false
	return _terrain_snapshot.size() == width and _terrain_snapshot[x][y] == 0


## 把相连的平台砖块分组，一组就是玩家眼里的"一块平台"
func platform_components() -> Array:
	const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var seen := {}
	var comps := []
	for x in width:
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
	for x in width:
		_terrain_snapshot.append(solid[x].duplicate())


func _restore_terrain() -> void:
	_invalidate_reach()
	for x in width:
		solid[x] = _terrain_snapshot[x].duplicate()


func _flatten_whole_corridor() -> void:
	for x in range(2, width - 2):
		_flatten_column(x, MAX_GROUND_ROW - 2)
	_snapshot_terrain()   # 地形变了，平台判定的基准也要跟着更新


# ---------------------------------------------------------------- 查询

func is_free(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < H and solid[x][y] == 0


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

## 能不能从一个落脚点移动到另一个。
##
## 判据直接来自 JumpModel 模拟出的真实轨迹：只要有**任意一条**轨迹沿途
## 扫过的格子全是空的，就算到得了。以前这里用"竖直上升 → 水平 → 下落"的
## L 形近似，既漏判（真实抛物线能钻过 L 形过不去的缺口）又误判
## （L 形没考虑身体宽度扫过的格子）。
func _can_move(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	for mask in JumpModel.masks_for(to_cell - from_cell):
		if _mask_clear(from_cell, mask):
			return true
	return false


func _mask_clear(origin: Vector2i, mask: PackedInt32Array) -> bool:
	for e in mask:
		# 内联解码：这是最内层循环，函数调用开销在这里很贵
		var x := origin.x + (e / 256 - 64)
		var y := origin.y + (e % 256 - 64)
		if x < 0 or x >= width or y < 0 or y >= H:
			return false
		if solid[x][y] == 1:
			return false
	return true


## 从入口做一次 BFS，返回所有能站上去的格子
func reachable_cells() -> Dictionary:
	if _reach_cache != null:
		return _reach_cache

	# 先把"能站人"的格子刷成位图，BFS 里每个候选点只查一次数组
	var standable: Array[PackedByteArray] = []
	for x in width:
		var col := PackedByteArray()
		col.resize(H)
		for y in H:
			col[y] = 1 if is_standable(x, y) else 0
		standable.append(col)

	var start := entrance_cell
	var visited := {}
	if start.x < 0 or start.x >= width or start.y < 0 or start.y >= H \
			or standable[start.x][start.y] == 0:
		_reach_cache = visited
		return visited

	var offsets := JumpModel.offsets()
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for off in offsets:
			var target: Vector2i = cell + off
			if target.x < 0 or target.x >= width or target.y < 0 or target.y >= H:
				continue
			if standable[target.x][target.y] == 0 or visited.has(target):
				continue
			if _can_move(cell, target):
				visited[target] = true
				queue.append(target)
	_reach_cache = visited
	return visited


func exit_reachable() -> bool:
	var goal := exit_cell
	if not is_standable(goal.x, goal.y):
		return false
	return reachable_cells().has(goal)


## 挑若干个互相隔开的可达落脚点，用来摆敌人。
## 比"按列取地面高度"通用：洞穴里没有唯一的地面，而且这样敌人也能刷在平台上。
func spawn_footholds(rng: RandomNumberGenerator, count: int, min_gap: int = 6) -> Array:
	var pool: Array[Vector2i] = []
	for cell in reachable_cells():
		var c: Vector2i = cell
		if c.x > entrance_cell.x + 6 and c.x < exit_cell.x - 4:
			pool.append(c)
	pool.shuffle()
	var chosen: Array[Vector2i] = []
	for c in pool:
		if chosen.size() >= count:
			break
		var ok := true
		for other in chosen:
			if absi(other.x - c.x) < min_gap and absi(other.y - c.y) < 4:
				ok = false
				break
		if ok:
			chosen.append(c)
	return chosen


func world_size() -> Vector2:
	return Vector2(width * TILE, H * TILE)


func tile_to_world(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * TILE, y * TILE)
