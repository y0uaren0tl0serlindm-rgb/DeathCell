extends Node
## 一次 "run"（从出生到死亡）的全局状态。
## 死亡时 reset_run() 清空，只有 meta 进度（图纸、永久强化）才应该保留在这里之外。

var cells: int = 0            ## 当前身上的细胞（死亡即失去）
var depth: int = 0            ## 当前是第几个房间
var run_seed: int = 0         ## 本次 run 的随机种子，用于程序化生成
var rng := RandomNumberGenerator.new()

## meta 进度（跨 run 保留），后续接存档
var meta_blueprints: Array[String] = []


func _ready() -> void:
	Events.request_next_room.connect(_on_request_next_room)


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


func _on_request_next_room() -> void:
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
