extends Node2D
## 游戏主循环：生成房间 → 放玩家进去 → 死亡/进门后重来。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const CellPickup = preload("res://src/pickups/cell_pickup.gd")
const Player = preload("res://src/player/player.gd")
const Room = preload("res://src/level/room.gd")

const RoomScene := preload("res://src/level/room.tscn")
const PlayerScene := preload("res://src/player/player.tscn")
const CellScene := preload("res://src/pickups/cell_pickup.tscn")

@onready var world: Node2D = $World

var room: Room
var player: Player
var _run_over := false


func _ready() -> void:
	Events.request_next_room.connect(_on_next_room)
	Events.enemy_died.connect(_on_enemy_died)
	Events.player_died.connect(func(): _run_over = true)
	_start_run()


func _process(_delta: float) -> void:
	# 用轮询而不是 _unhandled_input：不会被任何 UI 节点吞掉按键
	if _run_over and Input.is_action_just_pressed(&"restart"):
		Events.request_restart_run.emit()
		_start_run()


func _start_run() -> void:
	_run_over = false
	Engine.time_scale = 1.0
	Game.start_new_run()
	_build_room()
	_spawn_player()


func _build_room() -> void:
	if room and is_instance_valid(room):
		room.queue_free()
	room = RoomScene.instantiate() as Room
	world.add_child(room)
	room.generate(Game.room_rng(), Game.depth)


func _spawn_player() -> void:
	if player and is_instance_valid(player):
		player.queue_free()
	player = PlayerScene.instantiate() as Player
	world.add_child(player)
	player.global_position = room.entrance_position
	player.set_camera_limits(Rect2(Vector2.ZERO, room.world_size()))


## 进门：换新房间，玩家保留血量与武器。
## 顺序是写死的 —— 先推进深度，再用新深度生成房间。
## 不能让 Game 也去监听 request_next_room，那样正确性就取决于谁先注册（issue #3）。
func _on_next_room() -> void:
	Game.advance_depth()
	_build_room()
	if player and is_instance_valid(player):
		player.reset_for_room(room.entrance_position)
		player.set_camera_limits(Rect2(Vector2.ZERO, room.world_size()))


func _on_enemy_died(world_pos: Vector2, reward: int) -> void:
	# 拆成几颗掉落，视觉上更有"爆开"的感觉
	for value in Game.split_cell_reward(reward):
		var cell := CellScene.instantiate() as CellPickup
		world.add_child(cell)
		cell.global_position = world_pos + Vector2(randf_range(-4, 4), -12)
		cell.setup(value, Vector2(randf_range(-90, 90), randf_range(-190, -110)))
