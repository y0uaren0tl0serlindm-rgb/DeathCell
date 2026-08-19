extends Node
## 一次 "run"（从出生到死亡）的全局状态。
## 死亡时 reset_run() 清空，只有 meta 进度（图纸、永久强化）才应该保留在这里之外。

var cells: int = 0            ## 当前身上的细胞（死亡即失去）
var depth: int = 0            ## 当前是第几个房间
var run_seed: int = 0         ## 本次 run 的随机种子，用于程序化生成
var rng := RandomNumberGenerator.new()

## meta 进度（跨 run 保留），后续接存档
var meta_blueprints: Array[String] = []

const MAX_CELL_DROPS := 5


## 把击杀奖励拆成若干颗掉落物。余数要摊到前几颗上 ——
## 直接整除会把 8 拆成 5 颗 ×1 = 5，凭空吞掉 3 个细胞（issue #5）。
static func split_cell_reward(reward: int, max_drops: int = MAX_CELL_DROPS) -> PackedInt32Array:
	var out := PackedInt32Array()
	if reward <= 0:
		return out
	var drops := clampi(reward, 1, maxi(max_drops, 1))
	var base := reward / drops
	var remainder := reward % drops
	for i in drops:
		out.append(base + (1 if i < remainder else 0))
	return out


func start_new_run(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else randi()
	rng.seed = run_seed
	cells = 0
	depth = 0
	Events.cells_changed.emit(cells)
	Events.depth_changed.emit(depth)


func add_cells(amount: int) -> void:
	cells += amount
	Events.cells_changed.emit(cells)


func spend_cells(amount: int) -> bool:
	if cells < amount:
		return false
	cells -= amount
	Events.cells_changed.emit(cells)
	return true


## 推进到下一层。**只应该由 Main 这个流程协调者调用**。
## 以前这里挂在 Events.request_next_room 上，和 Main 的监听器抢执行顺序 ——
## 谁先跑决定了房间用新深度还是旧深度生成（issue #3）。信号只负责"通知"，
## 状态推进和房间生成的先后必须写死在一个地方。
func advance_depth() -> void:
	depth += 1
	Events.depth_changed.emit(depth)


## 每个房间用独立的 RNG，保证同一个 seed + depth 永远生成同一个房间。
func room_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(run_seed) + "_" + str(depth))
	return r


## 随深度提升的敌人强度曲线
func difficulty_scale() -> float:
	return 1.0 + depth * 0.18
