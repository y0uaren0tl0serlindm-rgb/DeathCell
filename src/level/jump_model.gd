class_name JumpModel
extends RefCounted
## 用 player.gd 的**真实物理常数**模拟跳跃，得出"从一个落脚点能到哪些落脚点"，
## 以及每条轨迹沿途身体扫过、因而必须保持空的格子。
##
## 为什么要模拟而不是手推：
## 之前 JUMP_UP / _max_dx() 是手算的近似值，代价是连续两次 bug ——
## 平台比跳跃能力高一格（issue #7），二层平台压掉一层的通行空间。
## 手推的数字和真实手感之间没有任何机制保证一致，改跳跃参数更是必然脱节。
## 现在这张表直接读 player.gd 的常量，改跳跃参数它自己就跟着变。
##
## 表是静态的、全局只算一次（约几毫秒），之后所有房间共用。

const PlayerScript = preload("res://src/player/player.gd")

const TILE := 16

## 玩家碰撞体尺寸，对应 player.tscn 里的 body_shape (10 × 22)，原点在脚底中心
const BODY_W := 10.0
const BODY_H := 22.0

const PHYSICS_DELTA := 1.0 / 60.0
const MAX_SIM_FRAMES := 160

## 只关心这个范围内的落点，再远的对关卡生成没意义
const MAX_DX := 9
const MAX_UP := 6
const MAX_DOWN := 14

## 每个落点最多保留几条轨迹。多存几条是因为不同弧线占用的格子不同，
## 有的被挡住时另一条也许还通得过。
const MAX_MASKS_PER_OFFSET := 3

# 模拟用的输入组合：横向意图 × 跳跃按住帧数 × 起跳后多久才推方向。
# hold = 0 表示不跳，直接走下悬崖。
# delay 存在的意义：先垂直起跳再横move，能钻进悬垂结构下面的位置。
## release：方向键按住几帧后松开。没有它的话包络会漏掉近距离落点 ——
## 一直按住方向的话加速度会让玩家直接飞过 1 格外的落点，
## 而真实玩家会点一下就松。漏掉的落点会让校验误判成"到不了"。
const SIM_DIRS := [-1, 0, 1]
const SIM_HOLDS := [0, 3, 6, 10, 16, 30, 60]
const SIM_DELAYS := [0, 4, 8, 14]
const SIM_RELEASES := [999, 2, 4, 7, 11, 18]

## Vector2i(dx, dy) → Array[PackedInt32Array]，每条是一份"必须为空"的格子清单
static var _moves: Dictionary = {}
static var _built := false


static func moves() -> Dictionary:
	if not _built:
		_build()
	return _moves


## 这个位移能不能到达（还没考虑地形阻挡）
static func can_reach(offset: Vector2i) -> bool:
	return moves().has(offset)


## 到达这个位移的所有候选轨迹，按占用格子数从少到多排序
static func masks_for(offset: Vector2i) -> Array:
	return moves().get(offset, [])


## 表里所有落点位移，BFS 直接拿它当邻接候选
static func offsets() -> Array:
	return moves().keys()


## 只用很小的横向位移就能上去的最大高度。
## 平台摆放用这个而不是绝对极限 —— 极限值往往要求近乎完美的长跳，
## 拿它当设计依据会做出"理论可达、实际难受"的关卡。
static func comfortable_rise() -> int:
	var best := 0
	for offset in moves():
		var o: Vector2i = offset
		if absi(o.x) <= 2 and o.y < 0:
			best = maxi(best, -o.y)
	return best


## 绝对能跳到的最大高度（格）
static func max_rise() -> int:
	var best := 0
	for offset in moves():
		best = maxi(best, -(offset as Vector2i).y)
	return best


## 同高度下能跨过的最远水平距离（格）
static func max_run() -> int:
	var best := 0
	for offset in moves():
		var o: Vector2i = offset
		if o.y == 0:
			best = maxi(best, absi(o.x))
	return best


# ---------------------------------------------------------------- 构建

static func _build() -> void:
	_built = true
	_moves = {}
	for dir in SIM_DIRS:
		for hold in SIM_HOLDS:
			for delay in SIM_DELAYS:
				if hold == 0 and delay > 0:
					continue   # 不跳的话延迟推方向没有意义
				for release in SIM_RELEASES:
					if dir == 0 and release != SIM_RELEASES[0]:
						continue   # 不推方向就没有松开一说
					_simulate(dir, hold, delay, release)
	_add_walk_moves()
	_sort_masks()


## 走路：模拟里没有地面，所有轨迹都是腾空的，于是"往旁边走一格"也被
## 当成一次小跳、要求头顶有起跳空间。平台底下净空正好一个身位时就会被
## 误判成过不去 —— 但玩家其实是走过去的，根本不起跳。
## 所以这里显式补上贴地移动：只要起点和落点站得住、身体占的格子是空的就行。
static func _add_walk_moves() -> void:
	for dx in [-1, 1]:
		# 平走一格
		_add_manual_move(Vector2i(dx, 0), [Vector2.ZERO, Vector2(dx * TILE, 0)])

		# 走到边缘迈一步、然后直直掉下去。
		# 这也是模拟表达不了的动作：模拟里没有地面，一开始就在腾空，
		# 所以"先贴地横move再下落"这条最常见的路线根本不会出现在表里。
		# 中间那一格不是落脚点，BFS 也没法把它拆成两步。
		var path: Array[Vector2] = [Vector2.ZERO]
		for dy in range(1, MAX_DOWN + 1):
			path.append(Vector2(dx * TILE, (dy - 1) * TILE))
			path.append(Vector2(dx * TILE, dy * TILE))
			_add_manual_move(Vector2i(dx, dy), path)


## 手工加一条移动：给定身体依次经过的位置，算出必须为空的格子
static func _add_manual_move(offset: Vector2i, positions: Array) -> void:
	var cells := {}
	for pos in positions:
		_add_body_cells(cells, pos)
	var mask := PackedInt32Array()
	for cell in cells:
		var c: Vector2i = cell
		mask.append(_encode(c.x, c.y))
	if not _moves.has(offset):
		_moves[offset] = []
	_moves[offset].append(mask)


## 跑一次跳跃，把沿途扫过的格子和每一次"可以落地"的时机记下来。
##
## 积分方式必须和 player.gd 的 _physics_process 一致：
## 先重力、再横向加速、最后 position += velocity * delta。
static func _simulate(dir: int, hold: int, delay: int, release: int = 999) -> void:
	var pos := Vector2.ZERO          # 脚底位置，相对起点
	var vel := Vector2.ZERO
	var jumping := hold > 0
	if jumping:
		vel.y = PlayerScript.JUMP_VELOCITY

	var swept := {}                  # Vector2i 集合：身体扫过的格子
	_add_body_cells(swept, pos)

	for frame in MAX_SIM_FRAMES:
		# 变高跳：松开按键时截断上升速度
		if jumping and frame == hold and vel.y < -60.0:
			vel.y *= PlayerScript.JUMP_CUT_MULT

		vel.y = minf(vel.y + PlayerScript.GRAVITY * PHYSICS_DELTA, PlayerScript.MAX_FALL_SPEED)

		var d := dir if (frame >= delay and frame < delay + release) else 0
		if d != 0:
			vel.x = move_toward(vel.x, d * PlayerScript.RUN_SPEED,
				PlayerScript.AIR_ACCEL * PHYSICS_DELTA)
		else:
			vel.x = move_toward(vel.x, 0.0, PlayerScript.AIR_FRICTION * PHYSICS_DELTA)

		var prev_y := pos.y
		pos += vel * PHYSICS_DELTA

		if absf(pos.x) > MAX_DX * TILE or pos.y > MAX_DOWN * TILE or pos.y < -MAX_UP * TILE:
			break

		# 先记落地，再把这一帧的身体格并进 swept。
		# 顺序不能反：越过格子下边界的那一帧，脚已经扎进了下面那一格，
		# 把它算进"必须为空"就等于要求落脚点底下是空的 —— 自相矛盾，
		# 结果是所有落点都被判成不可达。
		if vel.y > 0.0:
			var from_row := int(floor(prev_y / TILE))
			var to_row := int(floor(pos.y / TILE))
			for row in range(from_row + 1, to_row + 1):
				_record(int(round(pos.x / TILE)), row, swept)

		_add_body_cells(swept, pos)


## 把这一帧身体占的格子并进集合。
## 身体是 x ∈ [px-5, px+5]、y ∈ [py-22, py)，注意下边界开区间 ——
## py 这个点正好是脚底所踩实心格的顶面，不能算成"必须为空"。
static func _add_body_cells(swept: Dictionary, pos: Vector2) -> void:
	var c0 := _col(pos.x - BODY_W * 0.5)
	var c1 := _col(pos.x + BODY_W * 0.5)
	var r0 := _row(pos.y - BODY_H)
	var r1 := _row(pos.y - 0.001)
	for c in range(c0, c1 + 1):
		for r in range(r0, r1 + 1):
			swept[Vector2i(c, r)] = true


## 起点落脚格是 (0,0)，它纵向占 y ∈ [-TILE, 0)
static func _row(y: float) -> int:
	return int(floor(y / TILE)) + 1


## 起点落脚格横向以 x = 0 为中心
static func _col(x: float) -> int:
	return int(floor(x / TILE + 0.5))


static func _record(dx: int, dy: int, swept: Dictionary) -> void:
	if dx == 0 and dy == 0:
		return
	if absi(dx) > MAX_DX or dy < -MAX_UP or dy > MAX_DOWN:
		return
	# 落脚点下面那一格必须是实心的（不然站不住）。
	# 如果这条轨迹在到达之前从那一格里穿过去了，说明它是从台子内部飞过来的 ——
	# 真实玩家会撞在台子侧面上。这种轨迹不能算作"能落到这里"。
	# 少了这条判断，模型会声称一些实际上跳不上去的位置可达。
	if swept.has(Vector2i(dx, dy + 1)):
		return
	var offset := Vector2i(dx, dy)

	# 落点自己那一格和它上方的身体空间当然要空着，但不该把
	# 轨迹后半段（落地之后继续下坠的部分）算进来
	var mask := PackedInt32Array()
	for cell in swept:
		var c: Vector2i = cell
		mask.append(_encode(c.x, c.y))
	# 落点处身体占的格子
	var landing := {}
	_add_body_cells(landing, Vector2(dx * TILE, dy * TILE))
	for cell in landing:
		var c: Vector2i = cell
		var e := _encode(c.x, c.y)
		if not mask.has(e):
			mask.append(e)

	if not _moves.has(offset):
		_moves[offset] = []
	var list: Array = _moves[offset]
	if list.size() < 16:
		list.append(mask)


## 每个落点只留最省事的几条轨迹，按需要保持空的格子数从少到多
static func _sort_masks() -> void:
	for offset in _moves:
		var list: Array = _moves[offset]
		list.sort_custom(func(a, b): return a.size() < b.size())
		if list.size() > MAX_MASKS_PER_OFFSET:
			_moves[offset] = list.slice(0, MAX_MASKS_PER_OFFSET)


static func _encode(x: int, y: int) -> int:
	return (x + 64) * 256 + (y + 64)


static func decode_x(e: int) -> int:
	return e / 256 - 64


static func decode_y(e: int) -> int:
	return e % 256 - 64


## 调试用：把表打印成人看得懂的形状
static func describe() -> String:
	var m := moves()
	var lines: Array[String] = []
	lines.append("跳跃包络：%d 个落点，最高 %d 格，最远 %d 格，稳妥高度 %d 格"
		% [m.size(), max_rise(), max_run(), comfortable_rise()])
	for dy in range(-MAX_UP, 5):
		var row := "  dy=%+d " % dy
		for dx in range(-MAX_DX, MAX_DX + 1):
			row += "#" if m.has(Vector2i(dx, dy)) else "."
		lines.append(row)
	return "\n".join(lines)
