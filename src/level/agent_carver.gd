class_name AgentCarver
extends RefCounted
## 用**玩家的动作集合**当挖掘工具生成房间。
##
## 思路上和高度图生成器是相反的：
##   高度图：先随便造地形 → 再事后推导一堆约束去逼近"玩家能不能过去"
##   智能体：从入口出发，每一步只做 JumpModel 里真实存在的移动，走到出口为止；
##           走过的地方挖空、落脚点下面填实 —— **可达性是路径本身的性质**
##
## 这么做能删掉 corridor_ceiling 那类补丁逻辑：那些规则本质上是在补偿
## "生成时不知道玩家能干什么"。现在生成时知道了。
##
## 输出的是一整块石头里挖出来的洞穴，天然带竖井、分岔、回环 ——
## 高度图做不出这些，它永远是"一条地面 + 挂件"。

const JumpModel = preload("res://src/level/jump_model.gd")

const BORDER := 2            ## 左右封边厚度
const TOP_MARGIN := 2        ## 顶部保留的岩层
const BOTTOM_MARGIN := 2     ## 底部保留的岩层
const BODY_TILES := 2        ## 玩家身高（格）
const PATH_HEADROOM := 3     ## 主路径上方额外挖开几格（不挖的话通道正好一个身位，太憋屈）
const MAX_STEPS := 400
const STUCK_LIMIT := 8       ## 连续多少步没往右推进就强行开路
## 单步幅度上限。不限制的话智能体会挑大跨步，而大跨步的轨迹能扫过 50 格，
## 极容易撞上自己之前留下的支撑而被判非法 —— 走着走着就把自己堵死了。
const MAX_STEP_DX := 4
const MAX_STEP_DY := 4

var solid: Array[PackedByteArray] = []
var entrance_cell: Vector2i
var exit_cell: Vector2i
var path: Array[Vector2i] = []      ## 主路径上的落脚点，摆敌人和调试都用得上

var _w := 0
var _h := 0
var _rng: RandomNumberGenerator
var _carved := {}      ## 必须保持空的格子
var _protected := {}   ## 必须保持实心的格子（落脚点下面的支撑）
## 每一列的"期望高度"。没有它的话智能体会一路贴着地板走 ——
## 可下落的位移（最多 14 格）比可上升的（最多 3 格）多得多，
## 纯随机加权必然把它压到房间底部，上半部分整个浪费掉。
var _elevation: PackedInt32Array = PackedInt32Array()

## 候选位移只算一次。全表有 250+ 个位移，每步都遍历一遍再逐条验轨迹
## 是这里最大的开销，而我们只用得上小幅度的那些。
static var _step_offsets: Array = []


static func _offsets() -> Array:
	if _step_offsets.is_empty():
		for off in JumpModel.offsets():
			var o: Vector2i = off
			if absi(o.x) <= MAX_STEP_DX and absi(o.y) <= MAX_STEP_DY:
				_step_offsets.append(o)
	return _step_offsets


func carve(width: int, height: int, rng: RandomNumberGenerator,
		entrance_x: int, exit_x: int) -> void:
	_w = width
	_h = height
	_rng = rng
	_carved = {}
	_protected = {}
	path = []

	# 从一整块实心石头开始挖
	solid = []
	for x in _w:
		var col := PackedByteArray()
		col.resize(_h)
		col.fill(1)
		solid.append(col)

	_build_elevation()
	var cur := Vector2i(entrance_x, _elevation[entrance_x])
	entrance_cell = cur
	_stand_at(cur)

	var stuck := 0
	var furthest := cur.x
	for step in MAX_STEPS:
		if cur.x >= exit_x:
			break
		var next := _choose_move(cur, exit_x)
		if next == cur:
			# 一步都走不动（多半被自己protected的支撑围住了）→ 强行往右平推一格
			next = _force_forward(cur)
			if next == cur:
				break
		cur = next
		if cur.x > furthest:
			furthest = cur.x
			stuck = 0
		else:
			stuck += 1
			if stuck > STUCK_LIMIT:
				cur = _force_forward(cur)
				stuck = 0

	exit_cell = cur

	_open_landing(entrance_cell, 3)
	_open_landing(exit_cell, 3)
	_widen_path()
	_carve_pockets()
	_seal_borders()
	_fill_isolated_cavities()


## 一条平滑起伏的高度曲线，贯穿整个房间高度可用的区间
func _build_elevation() -> void:
	var top := TOP_MARGIN + JumpModel.MAX_UP + 1
	var bottom := _h - BOTTOM_MARGIN - 2
	_elevation = PackedInt32Array()
	_elevation.resize(_w)
	var y := bottom - _rng.randi_range(0, 2)
	var run := 0
	var dir := -1
	var hold := 0
	for x in _w:
		run -= 1
		if run <= 0:
			run = _rng.randi_range(8, 20)
			dir = _rng.randi_range(-1, 1)
			if y <= top + 2:
				dir = 1        # 太高了往回走
			elif y >= bottom - 1:
				dir = -1       # 太低了往上爬
		# 每两列才升降一格：坡太陡的话智能体每列都得起跳，很快就走不动
		hold += 1
		if hold >= 2:
			hold = 0
			y = clampi(y + dir, top, bottom)
		_elevation[x] = y


# ---------------------------------------------------------------- 走

## 在所有合法移动里挑一个。挑不到就返回原地。
func _choose_move(cur: Vector2i, exit_x: int) -> Vector2i:
	var candidates: Array = []
	var weights: Array[float] = []
	var total := 0.0

	for off in _offsets():
		var offset: Vector2i = off
		var target := cur + offset
		if not _target_ok(target):
			continue
		# 先算权重再验轨迹：权重是几次算术，验轨迹要扫几十个格子
		var weight := _weight_of(offset, cur, exit_x)
		if weight < 0.01:
			continue
		var mask := _usable_mask(cur, offset)
		if mask.is_empty():
			continue
		candidates.append([target, mask])
		weights.append(weight)
		total += weight

	if candidates.is_empty():
		return cur

	var roll := _rng.randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			var chosen: Array = candidates[i]
			_apply_move(cur, chosen[0], chosen[1])
			return chosen[0]
	var last: Array = candidates[candidates.size() - 1]
	_apply_move(cur, last[0], last[1])
	return last[0]


func _target_ok(target: Vector2i) -> bool:
	if target.x < BORDER + 1 or target.x > _w - BORDER - 2:
		return false
	if target.y < TOP_MARGIN + JumpModel.MAX_UP or target.y > _h - BOTTOM_MARGIN - 1:
		return false
	# 落脚点下面得放得下支撑
	if _carved.has(target + Vector2i(0, 1)):
		return false
	return true


## 找一条不会破坏已有支撑的轨迹；找不到返回空
func _usable_mask(cur: Vector2i, offset: Vector2i) -> PackedInt32Array:
	# 只看最省事的那条：masks 已按占用格数排序，挖掘用不着穷举
	for mask in JumpModel.masks_for(offset).slice(0, 1):
		var ok := true
		for e in mask:
			var c := Vector2i(cur.x + (e / 256 - 64), cur.y + (e % 256 - 64))
			if c.x < BORDER or c.x >= _w - BORDER or c.y <= TOP_MARGIN or c.y >= _h - 1:
				ok = false
				break
			if _protected.has(c):
				ok = false
				break
		if ok:
			return mask
	return PackedInt32Array()


## 往右推进优先，但要留出足够的上下起伏 —— 全走平的话又变回一条走廊了
func _weight_of(offset: Vector2i, cur: Vector2i, exit_x: int) -> float:
	var w := 0.0
	if offset.x > 0:
		w = 4.0
	elif offset.x == 0:
		w = 0.4
	else:
		w = 0.06     # 几乎不回头：往回走会一头扎进自己刚挖开的区域
	if offset.y != 0:
		w *= 1.5     # 鼓励垂直变化
	# 步子别总是迈到最大
	w /= 1.0 + absi(offset.x) * 0.2
	# 快到出口时收敛，别在门口反复横跳
	if cur.x > exit_x - 8 and offset.x <= 0:
		w *= 0.15
	# 贴着期望高度走：偏离越远权重掉得越快
	var target := cur + offset
	if target.x >= 0 and target.x < _w:
		var drift := absi(target.y - _elevation[target.x])
		w /= 1.0 + drift * drift * 0.35
	return w


func _apply_move(origin: Vector2i, target: Vector2i, mask: PackedInt32Array) -> void:
	for e in mask:
		_dig(Vector2i(origin.x + (e / 256 - 64), origin.y + (e % 256 - 64)))
	_stand_at(target)


## 卡住时的开路手段：沿期望高度往右铺一格。
##
## 关键约束：**绝不把已经挖开的格子重新填成支撑**。
## 填回去等于给先前挖通的路加了一堵墙，事后可达性校验就会失败 ——
## 之前 8% 的房间挖通了却过不了校验，就是栽在这里。
## 支撑位被占了就换个高度试，都不行就认输，交给外层换随机流重挖。
func _force_forward(cur: Vector2i) -> Vector2i:
	var nx := cur.x + 1
	if nx < BORDER + 1 or nx > _w - BORDER - 2:
		return cur
	var want: int = _elevation[nx] if nx < _elevation.size() else cur.y
	var preferred := cur.y + signi(want - cur.y)   # 一次只挪一格，保证跨得过去
	for ny in [preferred, cur.y, cur.y - 1, cur.y + 1]:
		var y := clampi(ny, TOP_MARGIN + JumpModel.MAX_UP, _h - BOTTOM_MARGIN - 1)
		var target := Vector2i(nx, y)
		if _carved.has(target + Vector2i(0, 1)):
			continue
		for x in [cur.x, nx]:
			for dy in range(0, BODY_TILES + 1):
				_dig(Vector2i(x, mini(cur.y, y) - dy))
		_stand_at(target)
		return target
	return cur


func _stand_at(cell: Vector2i) -> void:
	path.append(cell)
	_dig(cell)
	_dig(cell + Vector2i(0, -1))
	var support := cell + Vector2i(0, 1)
	if support.y < _h:
		solid[support.x][support.y] = 1
		_protected[support] = true


func _dig(c: Vector2i) -> void:
	if c.x < BORDER or c.x >= _w - BORDER or c.y <= TOP_MARGIN or c.y >= _h - 1:
		return
	if _protected.has(c):
		return
	solid[c.x][c.y] = 0
	_carved[c] = true


# ---------------------------------------------------------------- 修形

## 出入口挖出一小块平地，免得出生/进门卡在一格宽的台子上
func _open_landing(cell: Vector2i, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		var x := cell.x + dx
		if x < BORDER or x >= _w - BORDER:
			continue
		var support := Vector2i(x, cell.y + 1)
		# 同理：这一格要是先前挖通的路，填了就把路堵死了，宁可平台缺个口
		if not _carved.has(support):
			solid[support.x][support.y] = 1
			_protected[support] = true
		for dy in range(0, 4):
			_dig(Vector2i(x, cell.y - dy))


## 主路径上方多挖几格。不挖的话通道正好一个身位高，玩起来像在管道里爬。
func _widen_path() -> void:
	var extra: Array[Vector2i] = []
	for cell in _carved:
		var c: Vector2i = cell
		for dy in range(1, PATH_HEADROOM + 1):
			extra.append(Vector2i(c.x, c.y - dy))
	for c in extra:
		_dig(c)


## 沿路挖几个战斗空场。走廊里打架施展不开，需要有地方走位。
func _carve_pockets() -> void:
	if path.size() < 6:
		return
	var count := _rng.randi_range(3, 6)
	for i in count:
		var anchor: Vector2i = path[_rng.randi_range(2, path.size() - 2)]
		var half := _rng.randi_range(3, 5)
		var tall := _rng.randi_range(3, 5)
		for dx in range(-half, half + 1):
			for dy in range(0, tall + 1):
				_dig(Vector2i(anchor.x + dx, anchor.y - dy))


## 挖掘的副作用会留下一些和主空间不连通的封闭小洞。
## 它们里面的地面是"看得见站不上去"的落脚点 —— 正是 issue #7 抱怨的东西，
## 而且岩层里凭空多出空腔视觉上也奇怪。从主路径做一次空间连通性泛洪，
## 没被淹到的空格全部填回实心。
func _fill_isolated_cavities() -> void:
	const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var seen := {}
	var queue: Array[Vector2i] = []
	for cell in path:
		var c: Vector2i = cell
		if solid[c.x][c.y] == 0 and not seen.has(c):
			seen[c] = true
			queue.append(c)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in NEIGHBORS:
			var n: Vector2i = c + d
			if n.x < 0 or n.x >= _w or n.y < 0 or n.y >= _h:
				continue
			if solid[n.x][n.y] == 1 or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
	for x in _w:
		for y in _h:
			if solid[x][y] == 0 and not seen.has(Vector2i(x, y)):
				solid[x][y] = 1


func _seal_borders() -> void:
	for y in _h:
		for b in BORDER:
			solid[b][y] = 1
			solid[_w - 1 - b][y] = 1
	for x in _w:
		for b in TOP_MARGIN + 1:
			solid[x][b] = 1
		solid[x][_h - 1] = 1
