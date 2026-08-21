extends Node
## 纯状态测试：不生成房间，锁定 8 层、结算、解锁和选人规则。
##   godot --headless --path . res://tests/run_flow_test.tscn

const Door = preload("res://src/level/door.gd")
const Main = preload("res://src/main.gd")
const MainScene := preload("res://src/main.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	Game.begin_test_session()
	_check(Game.needs_first_run(), "新存档需要直接进入首局")

	Game.start_new_run(1001)
	_check(Game.run_active and Game.depth == 0, "首局从 L1 开始")
	_check(Game.current_character_id == Game.CHARACTER_RUSTY_SWORD, "首局强制锈剑")

	Game.add_cells(12)
	var death := Game.finish_run(Game.RunOutcome.DEATH)
	_check(death["carried_cells"] == 12 and death["bonus_cells"] == 0,
		"死亡结算带出全部本局细胞且无通关奖励")
	_check(Game.meta_cells == 12 and Game.cells == 0, "死亡细胞 100% 转入局外账户")
	_check(not Game.needs_first_run(), "完成首局后启用局外选人")

	# 重复结算不得重复入账。
	Game.finish_run(Game.RunOutcome.VICTORY)
	_check(Game.meta_cells == 12 and Game.finished_runs == 1, "同一局只能结算一次")

	var hammer_early := Game.choose_character(Game.CHARACTER_HEAVY_HAMMER)
	_check(not hammer_early["ok"], "重锤不能越过双匕提前解锁")
	var daggers := Game.choose_character(Game.CHARACTER_TWIN_DAGGERS)
	_check(daggers["ok"] and Game.meta_cells == 0, "消费 12 细胞解锁双匕")
	_check(Game.selected_character_id == Game.CHARACTER_TWIN_DAGGERS, "解锁后直接选中双匕")

	Game.start_new_run(1002)
	_check(Game.current_character_id == Game.CHARACTER_TWIN_DAGGERS, "第二局使用局外所选角色")
	for expected_depth in range(1, Game.TOTAL_FLOORS):
		_check(Game.advance_depth(), "可以推进到 L%d" % (expected_depth + 1))
		_check(Game.depth == expected_depth, "L%d 的 0-based 深度正确" % (expected_depth + 1))
	_check(Game.is_final_floor() and Game.depth == 7, "L8 是最终层")
	_check(not Game.advance_depth() and Game.depth == 7, "L8 后不存在第 9 层")

	Game.add_cells(5)
	var victory := Game.finish_run(Game.RunOutcome.VICTORY)
	_check(victory["reached_floor"] == 8, "通关结算记录抵达 L8")
	_check(victory["bonus_cells"] == Game.VICTORY_BONUS_CELLS, "通关发放额外细胞")
	_check(Game.meta_cells == 5 + Game.VICTORY_BONUS_CELLS, "通关携带与奖励一起入账")

	# 补足到重锤成本，验证第二段解锁曲线与选人结果。
	Game.start_new_run(1003)
	Game.add_cells(11)
	Game.finish_run(Game.RunOutcome.DEATH)
	var hammer := Game.choose_character(Game.CHARACTER_HEAVY_HAMMER)
	_check(hammer["ok"] and Game.meta_cells == 0, "按顺序消费 36 细胞解锁重锤")
	Game.start_new_run(1004)
	_check(Game.current_character_id == Game.CHARACTER_HEAVY_HAMMER, "新一局使用重锤角色")

	await _test_main_eight_floor_loop()
	_finish()


## 真实 Main + Room 的端到端检查。地图内部仍由当前生成器自由实现，
## 测试只跨 Room seam 观察层数、出口模式和最终结算。
func _test_main_eight_floor_loop() -> void:
	Game.begin_test_session()
	var main := MainScene.instantiate() as Main
	add_child(main)
	await _frames(5)
	_check(Game.depth == 0 and main.room.generated_depth == 0, "Main 从真实 L1 房间启动")

	for expected_depth in range(1, Game.TOTAL_FLOORS):
		Events.request_next_room.emit()
		await _frames(5)
		_check(Game.depth == expected_depth, "Main 进入真实 L%d" % (expected_depth + 1))
		_check(main.room.generated_depth == expected_depth,
			"L%d 房间按对应深度生成" % (expected_depth + 1))

	var final_door := main.room.get_node_or_null("Entities/Door") as Door
	_check(final_door != null and final_door._is_final, "L8 出口切换为终点传送门")
	_check(final_door != null and not final_door._unlocked, "终点传送门初始等待清怪")
	Events.room_cleared.emit()
	await _frames(1)
	_check(final_door != null and final_door._unlocked, "清怪后终点传送门开放")

	Events.request_next_room.emit()
	await _frames(3)
	var meta_screen := main.get_node("MetaScreen") as CanvasLayer
	_check(Game.depth == 7, "使用终点传送门后仍停在 L8，不生成 L9")
	_check(not Game.run_active and Game.last_settlement["outcome"] == Game.RunOutcome.VICTORY,
		"终点传送门触发通关结算")
	_check(meta_screen.visible and not main.world.visible, "通关后显示局外界面并收起局内世界")
	main.queue_free()
	await _frames(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\n流程状态测试全部通过")
	else:
		print("\n失败 %d 项：%s" % [_failures.size(), ", ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)
