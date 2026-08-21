extends Node2D
## 游戏流程协调者：局外整备 → 8 层 run → 死亡/通关结算 → 局外整备。
##
## 地图 seam 保持不变：这里只调用 Room.generate(rng, depth)，读取入口和世界尺寸。
## chunk 如何解析、模板如何拼、房间多宽，都封装在 Room / LevelGrid 内部。

# 显式 preload 跨文件的全局类，保证冷启动不依赖 .godot/ 类缓存。
const CellPickup = preload("res://src/pickups/cell_pickup.gd")
const Enemy = preload("res://src/enemies/enemy.gd")
const MetaScreen = preload("res://src/ui/meta_screen.gd")
const Player = preload("res://src/player/player.gd")
const Room = preload("res://src/level/room.gd")
const Weapons = preload("res://src/weapons/weapons.gd")

const RoomScene := preload("res://src/level/room.tscn")
const PlayerScene := preload("res://src/player/player.tscn")
const CellScene := preload("res://src/pickups/cell_pickup.tscn")

enum FlowState { RUNNING, SETTLING, META }

@onready var world: Node2D = $World
@onready var hud: CanvasLayer = $HUD
@onready var meta_screen: MetaScreen = $MetaScreen

var room: Room
var player: Player
var _flow_state := FlowState.META
var _remaining_enemies := 0
var _flow_token := 0
var _presented_settlement: Dictionary = {}


func _ready() -> void:
	Events.request_next_room.connect(_on_next_room)
	Events.enemy_died.connect(_on_enemy_died)
	Events.player_died.connect(_on_player_died)
	meta_screen.character_requested.connect(_on_character_requested)
	meta_screen.start_requested.connect(_on_start_requested)

	# 第 1 局强制锈剑、零选择摩擦；完成过一局后再从局外界面进入。
	if Game.needs_first_run():
		_start_run()
	else:
		_show_meta({})


func _start_run() -> void:
	_flow_token += 1   # 作废仍在等待死亡动画的旧结算协程（issue #4）
	_flow_state = FlowState.RUNNING
	_presented_settlement = {}
	Engine.time_scale = 1.0
	world.visible = true
	world.process_mode = Node.PROCESS_MODE_INHERIT
	hud.visible = true
	meta_screen.hide_screen()
	_clear_world()
	Game.start_new_run()
	_build_room()
	_spawn_player()


func _clear_world() -> void:
	for child in world.get_children():
		child.queue_free()
	room = null
	player = null
	_remaining_enemies = 0


func _build_room() -> void:
	# 换层时清掉旧房间和未捡的掉落；玩家由 reset_for_room() 跨层保留。
	for child in world.get_children():
		if child != player and not child.is_queued_for_deletion():
			child.queue_free()
	room = RoomScene.instantiate() as Room
	world.add_child(room)
	room.generate(Game.room_rng(), Game.depth)

	_refresh_remaining_enemies()
	if _remaining_enemies == 0:
		Events.room_cleared.emit()


func _spawn_player() -> void:
	if player and is_instance_valid(player):
		player.queue_free()
	player = PlayerScene.instantiate() as Player
	world.add_child(player)
	player.equip(Weapons.for_character(Game.current_character_id))
	player.global_position = room.entrance_position
	player.set_camera_limits(Rect2(Vector2.ZERO, room.world_size()))


## 出口是流程与地图之间唯一的控制 seam。
## L1~L7：先推进 depth，再生成对应房间；L8：不再推进，直接通关结算。
func _on_next_room() -> void:
	if _flow_state != FlowState.RUNNING or not Game.run_active:
		return
	if Game.is_final_floor():
		_finish_run(Game.RunOutcome.VICTORY)
		return
	if not Game.advance_depth():
		return
	_build_room()
	if player and is_instance_valid(player):
		player.reset_for_room(room.entrance_position)
		player.set_camera_limits(Rect2(Vector2.ZERO, room.world_size()))


func _on_enemy_died(world_pos: Vector2, reward: int) -> void:
	if _flow_state != FlowState.RUNNING:
		return
	# 敌人是在碰撞回调里死的，这会儿往场景里塞带碰撞体的节点会被引擎拒绝。
	_spawn_cells.call_deferred(world_pos, reward)
	_refresh_remaining_enemies()
	if _remaining_enemies == 0:
		Events.room_cleared.emit()


func _refresh_remaining_enemies() -> void:
	_remaining_enemies = 0
	if room == null or not is_instance_valid(room):
		return
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Enemy
		if enemy != null and room.is_ancestor_of(enemy) and enemy.state != Enemy.State.DEAD:
			_remaining_enemies += 1


func _spawn_cells(world_pos: Vector2, reward: int) -> void:
	if _flow_state != FlowState.RUNNING or not Game.run_active:
		return
	for value in Game.split_cell_reward(reward):
		var cell := CellScene.instantiate() as CellPickup
		world.add_child(cell)
		cell.global_position = world_pos + Vector2(randf_range(-4, 4), -12)
		cell.setup(value, Vector2(randf_range(-90, 90), randf_range(-190, -110)))


func _on_player_died() -> void:
	if _flow_state == FlowState.RUNNING:
		_finish_run(Game.RunOutcome.DEATH)


func _finish_run(outcome: int) -> void:
	if _flow_state != FlowState.RUNNING:
		return
	_flow_state = FlowState.SETTLING
	_flow_token += 1
	var token := _flow_token
	var settlement := Game.finish_run(outcome)

	if outcome == Game.RunOutcome.DEATH:
		# 留出死亡动作的可读时间；token 防止旧协程覆盖已经开始的新一局。
		await get_tree().create_timer(0.8, true, false, true).timeout
		if token != _flow_token:
			return
	_show_meta(settlement)


func _show_meta(settlement: Dictionary, message: String = "") -> void:
	_flow_state = FlowState.META
	Engine.time_scale = 1.0
	if not settlement.is_empty():
		_presented_settlement = settlement.duplicate(true)
	world.visible = false
	world.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	meta_screen.show_screen(Game.meta_snapshot(), _presented_settlement, message)


func _on_character_requested(character_id: String) -> void:
	if _flow_state != FlowState.META:
		return
	var result := Game.choose_character(character_id)
	_show_meta(_presented_settlement, result["message"])


func _on_start_requested() -> void:
	if _flow_state == FlowState.META:
		_start_run()
