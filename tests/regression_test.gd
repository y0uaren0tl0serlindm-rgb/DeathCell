extends Node
## 已修 bug 的回归测试，每一项对应一个 issue。
##   godot --headless --path . res://tests/regression_test.tscn
##
## 这里只放"曾经真的坏过"的行为。加新用例时请在标题里写清 issue 号，
## 这样以后有人改坏了能立刻知道自己踩回了哪个坑。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const AttackStep = preload("res://src/weapons/attack_step.gd")
const DamageInfo = preload("res://src/core/damage_info.gd")
const Enemy = preload("res://src/enemies/enemy.gd")
const Player = preload("res://src/player/player.gd")
const Room = preload("res://src/level/room.gd")
const WeaponData = preload("res://src/weapons/weapon_data.gd")

const MainScene := preload("res://src/main.tscn")

var _failures: Array[String] = []
var main: Node


func _ready() -> void:
	main = MainScene.instantiate()
	add_child(main)
	await _frames(10)

	await _test_issue_2_weapon_swap_during_attack()
	await _test_issue_3_depth_ordering()
	await _test_issue_4_stale_death_screen()
	await _test_issue_5_cell_reward_split()

	if _failures.is_empty():
		print("\n回归测试全部通过")
		get_tree().quit(0)
	else:
		print("\n失败 %d 项：%s" % [_failures.size(), ", ".join(_failures)])
		get_tree().quit(1)


# ---------------------------------------------------------------- #2

## 攻击中换武器不能污染这次攻击的伤害与时间轴
func _test_issue_2_weapon_swap_during_attack() -> void:
	print("\n[#2] 攻击中切换武器")
	var player := get_tree().get_first_node_in_group(&"player") as Player
	var weapon_before: WeaponData = player.weapon
	var name_before: String = weapon_before.display_name

	# 在前摇 / 判定 / 后摇三个阶段各试一次
	for phase_name in ["前摇", "判定", "后摇"]:
		await _wait_until_idle(player)
		Input.action_press(&"attack")
		await _frames(1)
		Input.action_release(&"attack")
		await _frames(1)

		match phase_name:
			"判定": await _frames(5)
			"后摇": await _frames(10)

		if player.state != Player.State.ATTACK:
			_fail("#2 %s 阶段没能进入攻击状态" % phase_name)
			continue

		var dmg_before: int = player.hitbox.damage
		var step_before: AttackStep = player._active_step

		Input.action_press(&"swap_weapon")
		await _frames(1)
		Input.action_release(&"swap_weapon")
		await _frames(1)

		_check(player.hitbox.damage == dmg_before,
			"#2 %s 阶段换武器后伤害不变 (%d)" % [phase_name, player.hitbox.damage])
		_check(player._active_step == step_before,
			"#2 %s 阶段换武器后招式时间轴不变" % phase_name)
		_check(player.weapon == weapon_before,
			"#2 %s 阶段攻击进行中当前武器不变" % phase_name)

		# 攻击结束后排队的换武器要生效
		await _wait_until_idle(player)
		_check(player.weapon != weapon_before,
			"#2 %s 阶段攻击结束后换武器生效（%s → %s）"
				% [phase_name, name_before, player.weapon.display_name])
		# 换回来，方便下一轮从同一把武器开始
		weapon_before = player.weapon
		name_before = weapon_before.display_name

	# 武器索引与实例必须一致，不能出现 HUD 显示 A 实际用 B
	_check(player.weapons[player.weapon_index] == player.weapon,
		"#2 weapon_index 与当前武器一致")


# ---------------------------------------------------------------- #3

## 连续进层：深度只加一次，且房间就是用这个深度生成的
func _test_issue_3_depth_ordering() -> void:
	print("\n[#3] 进层深度与生成参数一致")
	for i in 5:
		var before := Game.depth
		Events.request_next_room.emit()
		await _frames(6)
		_check(Game.depth == before + 1,
			"#3 第 %d 次进层深度只 +1（%d → %d）" % [i + 1, before, Game.depth])
		var room: Room = main.room
		_check(room != null and room.generated_depth == Game.depth,
			"#3 房间按当前深度生成（room=%d, game=%d）"
				% [room.generated_depth if room else -1, Game.depth])
		# 敌人数量是深度的函数，用它反查生成参数确实用了新深度
		var expected := clampi(4 + Game.depth, 4, 11)
		var actual := get_tree().get_nodes_in_group(&"enemy").size()
		_check(actual == expected,
			"#3 敌人数量符合当前深度（期望 %d，实际 %d）" % [expected, actual])

	# Game 不应该再自己监听这个信号，否则又会变成抢执行顺序
	var listeners := Events.request_next_room.get_connections().size()
	_check(listeners == 1, "#3 request_next_room 只有一个协调者监听（%d）" % listeners)


# ---------------------------------------------------------------- #4

## 死亡后 0.8 秒内快速重开，旧协程不能把死亡界面盖到新一局上
func _test_issue_4_stale_death_screen() -> void:
	print("\n[#4] 快速重开后的残留死亡界面")
	var hud := main.get_node("HUD")
	var death_screen: Control = hud.get_node("DeathScreen")
	var player := get_tree().get_first_node_in_group(&"player") as Player

	player.health.end_iframes()
	player.health.take_damage(DamageInfo.new(9999, Vector2.LEFT, null))
	await _frames(6)   # 远早于 0.8 秒的延迟
	_check(not death_screen.visible, "#4 死亡界面还在延迟中，此刻不该显示")

	Events.request_restart_run.emit()
	main._start_run()
	await _frames(90)  # 等到旧协程的 0.8 秒早已过去

	_check(not death_screen.visible, "#4 快速重开后死亡界面没有再冒出来")

	# 新一局里再死一次，界面仍然要正常工作
	var player2 := get_tree().get_first_node_in_group(&"player") as Player
	player2.health.end_iframes()
	player2.health.take_damage(DamageInfo.new(9999, Vector2.LEFT, null))
	await _frames(80)
	_check(death_screen.visible, "#4 新一局死亡后界面正常显示")

	Events.request_restart_run.emit()
	main._start_run()
	await _frames(10)


# ---------------------------------------------------------------- #5

## 掉落物价值总和必须等于配置的奖励
func _test_issue_5_cell_reward_split() -> void:
	print("\n[#5] 细胞奖励拆分不丢余数")
	var bad := 0
	for reward in range(1, 51):
		var parts := Game.split_cell_reward(reward)
		var total := 0
		for v in parts:
			total += v
		if total != reward:
			bad += 1
			if bad <= 3:
				print("      reward=%d 拆成 %s 总和=%d" % [reward, parts, total])
		if parts.size() > Game.MAX_CELL_DROPS:
			bad += 1
	_check(bad == 0, "#5 奖励 1~50 拆分后总和都等于原值")

	# issue 里点名的例子：Brute 的 8 个细胞
	var brute_parts := Game.split_cell_reward(8)
	var brute_total := 0
	for v in brute_parts:
		brute_total += v
	_check(brute_total == 8 and brute_parts.size() <= 5,
		"#5 Brute 奖励 8 拆成 %s（%d 颗，总和 %d）"
			% [brute_parts, brute_parts.size(), brute_total])

	# 端到端：真的杀一个 Brute，把细胞收干净
	var brute := preload("res://src/enemies/brute.tscn").instantiate() as Enemy
	main.world.add_child(brute)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	brute.global_position = player.global_position + Vector2(30, 0)
	await _frames(2)
	var cells_before := Game.cells
	var reward: int = brute.cell_reward
	brute.health.take_damage(DamageInfo.new(99999, Vector2.RIGHT, null))
	await _frames(150)
	_check(Game.cells - cells_before == reward,
		"#5 击杀 Brute 实际到手 %d（配置 %d）" % [Game.cells - cells_before, reward])


# ---------------------------------------------------------------- 工具

func _wait_until_idle(player: Player) -> void:
	for i in 200:
		if player.state == Player.State.IDLE or player.state == Player.State.RUN:
			return
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _fail(label: String) -> void:
	print("  FAIL  ", label)
	_failures.append(label)
