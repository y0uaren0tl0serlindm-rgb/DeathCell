extends Node
## 把跳跃模型和**真实玩家**对齐的测试。
##   godot --headless --path . res://tests/jump_model_test.tscn
##
## JumpModel 是从 player.gd 的常量模拟出来的，但"读了同样的常量"不等于
## "算出了同样的结果"—— 积分顺序、碰撞体尺寸、move_and_slide 的行为
## 都可能让模型和真实手感脱节，而整个关卡生成的可达性保证都建立在这个模型上。
##
## 所以这里不测模型自己，而是搭一个受控的小场地，放进真正的 Player 场景，
## 用真实输入去跳，看结论对不对得上。

const PlayerScene = preload("res://src/player/player.tscn")
const JumpModel = preload("res://src/level/jump_model.gd")

const TILE := 16
const GROUND_Y := 400.0     ## 起跳地面的表面高度
const EDGE_X := 300.0       ## 台子/空隙的左缘
const MAX_TRY_FRAMES := 110

var _failures: Array[String] = []
var _world: Node2D


func _ready() -> void:
	print("跳跃包络：最高 %d 格 / 稳妥 %d 格 / 平跳最远 %d 格"
		% [JumpModel.max_rise(), JumpModel.comfortable_rise(), JumpModel.max_run()])

	# --- 垂直 ---
	var rise := JumpModel.comfortable_rise()
	_check(await _can_climb(rise), "模型说 %d 格跳得上去，真玩家做到了" % rise)

	var too_high := JumpModel.max_rise() + 1
	_check(not await _can_climb(too_high),
		"模型说 %d 格跳不上去，真玩家也确实上不去" % too_high)

	# --- 水平 ---
	var run := JumpModel.max_run()
	var ok_gap := run - 2
	_check(await _can_cross(ok_gap), "模型说 %d 格空隙跨得过，真玩家做到了" % ok_gap)

	var wide_gap := run + 3
	_check(not await _can_cross(wide_gap),
		"模型说 %d 格空隙跨不过，真玩家也确实跨不过" % wide_gap)

	if _failures.is_empty():
		print("\n跳跃模型与真实玩家一致")
		get_tree().quit(0)
	else:
		print("\n不一致 %d 项：%s" % [_failures.size(), ", ".join(_failures)])
		print("跳跃模型已经和 player.gd 脱节，关卡生成的可达性保证随之失效。")
		get_tree().quit(1)


# ---------------------------------------------------------------- 场地

func _reset_world() -> void:
	if _world and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	_world = Node2D.new()
	add_child(_world)
	var body := StaticBody2D.new()
	body.name = "Terrain"
	body.collision_layer = 1
	body.collision_mask = 0
	_world.add_child(body)


func _add_box(rect: Rect2) -> void:
	var body: StaticBody2D = _world.get_node("Terrain")
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	shape.position = rect.position + rect.size * 0.5
	body.add_child(shape)


func _spawn_player(x: float) -> Player:
	var p := PlayerScene.instantiate() as Player
	_world.add_child(p)
	p.global_position = Vector2(x, GROUND_Y)
	for i in 20:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	return p


# ---------------------------------------------------------------- 垂直

## 贴着台子侧面往上跳。试遍各种"起跳后多久推方向"的时机。
## 正下方是跳不上去的（会顶到台子底面），所以玩家站在台子边上、
## 先垂直起跳、再横move到台面上 —— 这也正是关卡生成摆平台时假定的路线。
func _can_climb(height: int) -> bool:
	for delay in [0, 3, 6, 9, 12, 15, 18]:
		await _reset_world()
		var top := GROUND_Y - height * TILE
		_add_box(Rect2(0, GROUND_Y, EDGE_X, 200))
		_add_box(Rect2(EDGE_X, top, 400, GROUND_Y - top + 200))
		var p := await _spawn_player(EDGE_X - 12.0)

		Input.action_press(&"jump")
		var reached := false
		for i in MAX_TRY_FRAMES:
			if i == delay:
				Input.action_press(&"move_right")
			await get_tree().physics_frame
			if not is_instance_valid(p):
				break
			if p.is_on_floor() and p.global_position.y <= top + 1.0:
				reached = true
				break
		_release_all()
		if reached:
			return true
	return false


# ---------------------------------------------------------------- 水平

## 助跑 N 帧后起跳，看能不能落到对面
func _can_cross(gap: int) -> bool:
	for run_up in [0, 6, 12, 20, 30]:
		await _reset_world()
		var far_x := EDGE_X + gap * TILE
		_add_box(Rect2(0, GROUND_Y, EDGE_X, 200))
		_add_box(Rect2(far_x, GROUND_Y, 400, 200))
		var p := await _spawn_player(EDGE_X - 110.0)

		Input.action_press(&"move_right")
		var crossed := false
		for i in MAX_TRY_FRAMES:
			if i == run_up:
				Input.action_press(&"jump")
			await get_tree().physics_frame
			if not is_instance_valid(p):
				break
			if p.is_on_floor() and p.global_position.x >= far_x:
				crossed = true
				break
			if p.global_position.y > GROUND_Y + 40.0:
				break   # 掉进坑里了
		_release_all()
		if crossed:
			return true
	return false


func _release_all() -> void:
	for a in [&"jump", &"move_right", &"move_left"]:
		Input.action_release(a)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_failures.append(label)
