extends Node
## 无头冒烟测试：验证核心链路没断。
##   godot --headless --path . res://tests/smoke_test.tscn

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const DamageInfo = preload("res://src/core/damage_info.gd")
const Enemy = preload("res://src/enemies/enemy.gd")
const HeroSprite = preload("res://assets/characters/player/runtime/hero_sprite.gd")
const Player = preload("res://src/player/player.gd")
const Room = preload("res://src/level/room.gd")
const Weapons = preload("res://src/weapons/weapons.gd")

const MainScene := preload("res://src/main.tscn")

var _failures: Array[String] = []
var main: Node


func _ready() -> void:
	Game.begin_test_session()
	main = MainScene.instantiate()
	add_child(main)
	await _frames(10)

	var player := get_tree().get_first_node_in_group(&"player") as Player
	_check(player != null, "玩家已生成")
	var enemies := get_tree().get_nodes_in_group(&"enemy")
	_check(enemies.size() >= 4, "房间里生成了敌人 (%d)" % enemies.size())
	if player == null or enemies.is_empty():
		_finish()
		return
	# 冒烟测试只留一个静止靶子验证命中；其余敌人若继续追击，随机地形下会
	# 把玩家打进 HURT，令“按攻击”偶发失效，测到的是战斗干扰而不是攻击链路。
	for enemy_node in enemies:
		(enemy_node as Enemy).set_physics_process(false)

	# 玩家应当站在地面上，而不是卡在墙里或掉出世界
	await _wait_until_grounded(player, 120)
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
	enemy.health.take_damage(DamageInfo.new(9999, Vector2.RIGHT, null))
	await _frames(120)
	_check(Game.cells > cells_before, "击杀后拾取到细胞 (%d)" % Game.cells)

	# --- 进入下一层 ---
	var depth_before := Game.depth
	Events.request_next_room.emit()
	await _frames(2)
	for enemy_node in get_tree().get_nodes_in_group(&"enemy"):
		(enemy_node as Enemy).set_physics_process(false)
	_check(Game.depth == depth_before + 1, "进门后深度 +1 (%d)" % Game.depth)
	_check(get_tree().get_nodes_in_group(&"enemy").size() > 0, "新房间重新生成了敌人")
	player = get_tree().get_first_node_in_group(&"player") as Player
	await _wait_until_grounded(player, 120)
	_check(player.is_on_floor(), "新房间入口可站立")

	# 回归：房间的 _draw() 铺满整块背景，新房间又是后加进 world 的，
	# 所以房间必须待在玩家下面一层，否则换房间后玩家会被背景盖住看不见
	# 用预加载的类型判断，不要用 find_children(..., "Room") ——
	# 那个靠字符串查全局类注册表，冷启动没有缓存时查不到（issue #8）
	var rooms: Array[Node] = []
	for child in main.world.get_children():
		if child is Room:
			rooms.append(child)
	_check(rooms.size() == 1, "同时只存在一个房间 (%d)" % rooms.size())
	if rooms.size() > 0:
		_check((rooms[0] as Node2D).z_index < player.z_index,
			"房间在玩家下层 (room z=%d, player z=%d)" % [(rooms[0] as Node2D).z_index, player.z_index])

	# --- 死亡 ---
	# 注意：GDScript 的 lambda 按值捕获局部变量，所以用数组当引用容器
	var died := [false]
	Events.player_died.connect(func(): died[0] = true)
	var carried_cells := Game.cells
	print("    (致命一击前 无敌=%s 血量=%d)" % [player.health.is_invulnerable, player.health.current])
	player.health.end_iframes()   # 这里测的是死亡流程，不是无敌帧
	player.health.take_damage(DamageInfo.new(9999, Vector2.LEFT, null))
	await _frames(5)
	_check(died[0], "玩家死亡事件触发")

	# --- 死亡结算 → 局外界面 → 新一局 ---
	await _frames(60)
	var meta_screen := main.get_node("MetaScreen") as CanvasLayer
	_check(meta_screen.visible, "死亡动作后进入局外结算界面")
	_check(Game.meta_cells == carried_cells,
		"死亡时本局细胞 100%% 入账（%d）" % Game.meta_cells)
	_check(not Game.run_active, "结算后本局已结束")
	main._on_start_requested()
	await _frames(20)
	_check(Game.depth == 0 and Game.cells == 0, "从局外开始新一局：深度与本局细胞归零")
	var new_player := get_tree().get_first_node_in_group(&"player") as Player
	_check(new_player != null and new_player.health.current == new_player.health.max_health,
		"重开后玩家满血复活")
	_check(is_equal_approx(Engine.time_scale, 1.0), "时间缩放已恢复正常 (%.2f)" % Engine.time_scale)

	_check_combo_animations()

	_finish()


## 每一把武器的每一段招式都必须指向一套真实存在的攻击贴图。
##
## 表现层以前用 `_combo_index % 2` 在两套贴图之间轮换，锈剑三段配两套贴图
## 就播成 A-B-A —— 三下连招看起来只有两下，玩家读不出连招打到哪了。
## 段数和贴图数是各自变化的两个量，取模只在两者相等时碰巧成立。
## 现在 AttackStep.anim 把这层对应关系写成了数据，这一项负责在加招式、
## 或者删掉某套贴图时立刻报出来。
func _check_combo_animations() -> void:
	var known := HeroSprite.attack_anim_names()
	for w in Weapons.all():
		_check(not w.combo.is_empty(), "%s 有连招数据" % w.display_name)
		for i in w.combo.size():
			var anim: StringName = w.combo[i].anim
			_check(anim in known,
				"%s 第 %d 段指定的动画存在（%s）" % [w.display_name, i + 1, anim])
		# 段数超过贴图数时必然有两段共用同一套动画，玩家会以为连招断了。
		# 要加第三段，先让美术出第三套斩击。
		_check(w.combo.size() <= known.size(),
			"%s 的连招段数（%d）没有超过可用攻击动画数（%d）"
				% [w.display_name, w.combo.size(), known.size()])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait_until_grounded(player: Player, max_frames: int) -> void:
	for i in max_frames:
		if player.is_on_floor():
			return
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
