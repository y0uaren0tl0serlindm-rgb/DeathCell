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
const Weapons = preload("res://src/weapons/weapons.gd")

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
	await _test_issue_6_room_transition_clears_queue()
	await _test_issue_9_intent_slot()

	if _failures.is_empty():
		print("\n回归测试全部通过")
		get_tree().quit(0)
	else:
		print("\n失败 %d 项：%s" % [_failures.size(), ", ".join(_failures)])
		get_tree().quit(1)


# ---------------------------------------------------------------- #2

## 攻击中换武器不能污染这次攻击的伤害与时间轴。
##
## 玩家已经没有换武器的输入了（武器绑定角色），但这条不变量依然要守：
## 掉落/词条系统迟早会在任意时刻调 Player.equip()，而伤害和时间轴走的是
## _enter_attack() 时锁定的 _active_weapon / _active_step。
## 所以测试从"按 K 键"改成"直接调 equip()"，测的还是同一件事。
func _test_issue_2_weapon_swap_during_attack() -> void:
	print("\n[#2] 攻击中切换武器")
	var player := get_tree().get_first_node_in_group(&"player") as Player
	var weapon_before: WeaponData = player.weapon

	# 在前摇 / 判定 / 后摇三个阶段各试一次
	for phase_name in ["前摇", "判定", "后摇"]:
		await _wait_until_idle(player)
		player.equip(weapon_before)
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

		var incoming := Weapons.heavy_hammer()   # 数值和时间轴都和锈剑差得很远
		player.equip(incoming)
		await _frames(1)

		_check(player.hitbox.damage == dmg_before,
			"#2 %s 阶段换武器后伤害不变 (%d)" % [phase_name, player.hitbox.damage])
		_check(player._active_step == step_before,
			"#2 %s 阶段换武器后招式时间轴不变" % phase_name)
		_check(player._active_weapon == weapon_before,
			"#2 %s 阶段这一击仍然结算在旧武器上" % phase_name)

		# 但下一次起手要用新武器
		await _wait_until_idle(player)
		_check(player.weapon == incoming,
			"#2 %s 阶段攻击结束后已经换成新武器（%s）"
				% [phase_name, player.weapon.display_name])
		await _tap(&"attack")
		await _frames(2)
		_check(player._active_weapon == incoming,
			"#2 %s 阶段下一次起手用的是新武器" % phase_name)
		await _run_until_idle(player, 200)

	player.equip(weapon_before)


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


# ---------------------------------------------------------------- #6

## 换房间必须清掉上一房间的攻击上下文和排队输入
func _test_issue_6_room_transition_clears_queue() -> void:
	print("\n[#6] 换房间清理瞬时状态")
	await _clear_enemies()
	var player := get_tree().get_first_node_in_group(&"player") as Player
	# 重锤的取消点在 0.54 秒，够我们从容地塞两个意图进去再进门。
	# 换成锈剑的话槽里的翻滚可能在进门前就兑现掉，测的东西就没了。
	await _equip(player, Weapons.heavy_hammer())
	await _wait_until_idle(player)
	var weapon_before: WeaponData = player.weapon
	var hp_before: int = player.health.current

	# 攻击中先预约续击，再用翻滚把它覆盖掉（意图槽只留最后一个）
	Input.action_press(&"attack")
	await _frames(1)
	Input.action_release(&"attack")
	await _frames(2)
	if player.state != Player.State.ATTACK:
		_fail("#6 没能进入攻击状态")
		return
	await _tap(&"attack")
	_check(player._pending_intent == Player.Intent.ATTACK, "#6 攻击中按攻击进入意图槽")
	await _tap(&"roll")
	_check(player._pending_intent == Player.Intent.ROLL, "#6 翻滚覆盖了尚未开始的续击")

	# 攻击还没结束就进门
	_check(player.state == Player.State.ATTACK, "#6 进门时仍在攻击中")
	Events.request_next_room.emit()
	await _frames(6)
	await _clear_enemies()

	_check(player._pending_intent == Player.Intent.NONE, "#6 进新房间后待执行意图已清除")
	_check(player._active_step == null and player._active_weapon == null,
		"#6 进新房间后攻击上下文已清除")
	_check(player.weapon == weapon_before,
		"#6 已装备的武器跨房间保留（%s）" % player.weapon.display_name)
	_check(player.health.current == hp_before,
		"#6 血量跨房间保留（%d）" % player.health.current)

	# 新房间里完整打一套，结束时不能冒出上一房间遗留的翻滚
	await _wait_until_idle(player)
	Input.action_press(&"attack")
	await _frames(1)
	Input.action_release(&"attack")
	var stray_roll := false
	for i in 90:
		await get_tree().physics_frame
		if player.state == Player.State.ROLL:
			stray_roll = true
			break
	_check(not stray_roll, "#6 新房间攻击结束后没有触发遗留的翻滚")
	await _equip(player, Weapons.rusty_sword())


# ---------------------------------------------------------------- #9

## 攻击输入的意图槽：只留一个、可被覆盖、不过期、连招有终点
func _test_issue_9_intent_slot() -> void:
	print("\n[#9] 攻击意图槽")
	await _clear_enemies()
	var player := get_tree().get_first_node_in_group(&"player") as Player

	# --- A. 第一击内狂点，最多只多打出一击 ---
	_equip(player, Weapons.heavy_hammer())     # 重锤第一击够长，塞得下 10 次点击
	await _wait_until_idle(player)
	await _tap(&"attack")
	await _frames(2)
	var max_index := 0
	for i in 10:
		await _tap(&"attack")
		max_index = maxi(max_index, player._combo_index)
	var left_attack := await _run_until_idle(player, 200)
	max_index = maxi(max_index, left_attack)
	_check(max_index <= 1, "#9 第一击内点 10 次最多只多打出一击（最远打到第 %d 段）" % (max_index + 1))

	# --- B. 分布点击也不能越过末段无限循环 ---
	var sword := Weapons.rusty_sword()
	var last_step := sword.combo.size() - 1     # 别写死段数，加招式时这里要自己跟上
	_equip(player, sword)
	await _wait_until_idle(player)
	var seen_idle := false
	var deepest := 0
	for i in 90:                                # 约 1.5 秒，每 3 帧点一次
		if i % 3 == 0:
			Input.action_press(&"attack")
		else:
			Input.action_release(&"attack")
		await get_tree().physics_frame
		if player.state == Player.State.ATTACK:
			deepest = maxi(deepest, player._combo_index)
		else:
			seen_idle = true
	Input.action_release(&"attack")
	_check(deepest <= last_step, "#9 持续点击没有越过 %d 段连招的末段（最远第 %d 段）"
		% [sword.combo.size(), deepest + 1])
	_check(seen_idle, "#9 连招打完会退出攻击状态，不是一直循环")

	# --- C. 更新的意图能覆盖尚未开始的续击 ---
	for case in [[&"roll", Player.Intent.ROLL], [&"jump", Player.Intent.JUMP],
			[&"move_left", Player.Intent.MOVE]]:
		await _equip(player, Weapons.heavy_hammer())
		await _wait_until_idle(player)
		await _tap(&"attack")
		await _frames(3)
		await _tap(&"attack")
		if player._pending_intent != Player.Intent.ATTACK:
			_fail("#9 覆盖测试的前置条件没满足（%s）" % case[0])
			continue
		await _tap(case[0])
		_check(player._pending_intent == case[1],
			"#9 %s 覆盖了尚未开始的续击" % case[0])
		await _run_until_idle(player, 200)

	# --- D. 起手就按翻滚不会过期（复现方式 B）---
	for w in [Weapons.rusty_sword(), Weapons.heavy_hammer()]:
		await _equip(player, w)
		await _wait_until_idle(player)
		await _tap(&"attack")
		await _tap(&"roll")                     # 远早于取消点
		var rolled := false
		for i in 120:
			await get_tree().physics_frame
			if player.state == Player.State.ROLL:
				rolled = true
				break
		_check(rolled, "#9 %s 起手按翻滚仍能在取消点执行" % w.display_name)
		await _run_until_idle(player, 200)

	# --- E. 显式配置的循环连招 ---
	var looping := Weapons.rusty_sword()
	looping.loops = true
	looping.display_name = "测试用循环武器"
	await _equip(player, looping)
	await _wait_until_idle(player)
	var looped := false
	for i in 120:
		if i % 3 == 0:
			Input.action_press(&"attack")
		else:
			Input.action_release(&"attack")
		await get_tree().physics_frame
		if player.state == Player.State.ATTACK and player._combo_index >= looping.combo.size():
			looped = true
			break
	Input.action_release(&"attack")
	_check(looped, "#9 显式开启 loops 的武器可以循环连招")
	await _equip(player, Weapons.rusty_sword())
	await _run_until_idle(player, 200)


## 这几项测的是输入语义，不该受战斗干扰：
## 敌人打中玩家会走 _on_damaged → _resolve_intent_after_attack()，把意图槽清掉，
## 断言就变成随机失败。换成洞穴地形后敌人更容易贴上来，偶发概率明显上升。
func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _equip(player: Player, w: WeaponData) -> void:
	# 别在出招途中换 —— 那是 issue #2 明确禁止的事
	await _run_until_idle(player, 200)
	player.equip(w)
	player.clear_transient_state()


## 按一下再松开
func _tap(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


## 跑到玩家离开攻击状态为止，返回过程中最深的连招段号
func _run_until_idle(player: Player, max_frames: int) -> int:
	var deepest := 0
	for i in max_frames:
		if player.state != Player.State.ATTACK:
			return deepest
		deepest = maxi(deepest, player._combo_index)
		await get_tree().physics_frame
	return deepest


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
