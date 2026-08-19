extends Node
## 无头冒烟测试：验证核心链路没断。
##   godot --headless --path . res://tests/smoke_test.tscn

const MainScene := preload("res://src/main.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await _frames(10)

	var player := get_tree().get_first_node_in_group(&"player") as Player
	_check(player != null, "玩家已生成")
	var enemies := get_tree().get_nodes_in_group(&"enemy")
	_check(enemies.size() >= 4, "房间里生成了敌人 (%d)" % enemies.size())
	if player == null or enemies.is_empty():
		_finish()
		return

	# 玩家应当站在地面上，而不是卡在墙里或掉出世界
	await _frames(30)
	_check(player.is_on_floor(), "玩家落地并站稳 (y=%.1f)" % player.global_position.y)

	# --- 攻击命中 ---
	var enemy := enemies[0] as Enemy
	enemy.global_position = player.global_position + Vector2(22, 0)
	enemy.set_physics_process(false)   # 定住靶子，避免它自己跑掉
	await _frames(2)
	var hp_before: int = enemy.health.current
	await _press(&"attack", 25)
	_check(enemy.health.current < hp_before, "攻击造成伤害 (%d → %d)" % [hp_before, enemy.health.current])

	# --- 翻滚无敌帧 ---
	await _press(&"roll", 6)
	_check(player.health.is_invulnerable, "翻滚中处于无敌状态")
	await _frames(30)

	# --- 击杀掉细胞 ---
	var cells_before := Game.cells
	enemy.health.take_damage(DamageInfo.create(9999, Vector2.RIGHT, null))
	await _frames(120)
	_check(Game.cells > cells_before, "击杀后拾取到细胞 (%d)" % Game.cells)

	# --- 进入下一层 ---
	var depth_before := Game.depth
	Events.request_next_room.emit()
	await _frames(10)
	_check(Game.depth == depth_before + 1, "进门后深度 +1 (%d)" % Game.depth)
	_check(get_tree().get_nodes_in_group(&"enemy").size() > 0, "新房间重新生成了敌人")
	player = get_tree().get_first_node_in_group(&"player") as Player
	await _frames(40)
	_check(player.is_on_floor(), "新房间入口可站立")

	# 回归：房间的 _draw() 铺满整块背景，新房间又是后加进 world 的，
	# 所以房间必须待在玩家下面一层，否则换房间后玩家会被背景盖住看不见
	var rooms := get_tree().root.find_children("*", "Room", true, false)
	_check(rooms.size() == 1, "同时只存在一个房间 (%d)" % rooms.size())
	if rooms.size() > 0:
		_check((rooms[0] as Node2D).z_index < player.z_index,
			"房间在玩家下层 (room z=%d, player z=%d)" % [(rooms[0] as Node2D).z_index, player.z_index])

	# --- 死亡 ---
	# 注意：GDScript 的 lambda 按值捕获局部变量，所以用数组当引用容器
	var died := [false]
	Events.player_died.connect(func(): died[0] = true)
	print("    (致命一击前 无敌=%s 血量=%d)" % [player.health.is_invulnerable, player.health.current])
	player.health.end_iframes()   # 这里测的是死亡流程，不是无敌帧
	player.health.take_damage(DamageInfo.create(9999, Vector2.LEFT, null))
	await _frames(5)
	_check(died[0], "玩家死亡事件触发")

	# --- 死亡后重开 ---
	await _frames(60)
	Input.action_press(&"restart")
	await _frames(2)
	Input.action_release(&"restart")
	await _frames(20)
	_check(Game.depth == 0 and Game.cells == 0, "按 R 重开：深度与细胞归零")
	var new_player := get_tree().get_first_node_in_group(&"player") as Player
	_check(new_player != null and new_player.health.current == new_player.health.max_health,
		"重开后玩家满血复活")
	_check(is_equal_approx(Engine.time_scale, 1.0), "时间缩放已恢复正常 (%.2f)" % Engine.time_scale)

	_finish()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _press(action: StringName, hold_frames: int) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(hold_frames)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("\n冒烟测试全部通过")
	else:
		print("\n失败 %d 项：%s" % [_failures.size(), ", ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)
