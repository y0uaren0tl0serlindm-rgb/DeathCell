extends Node
## 打击感相关的全局效果：顿帧（hitstop）、震屏、飘字。
## 死亡细胞的手感有一半来自这三样，所以做成全局的、任何地方一行就能调用。

signal shake_requested(trauma: float)

const DamageNumberScene := preload("res://src/fx/damage_number.tscn")

var _hitstop_until_msec: int = 0
var _hitstop_token: int = 0


func _ready() -> void:
	# time_scale = 0 的时候自身仍然要跑
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	# 兜底：万一某次 await 没能恢复（场景切换、节点被释放……），
	# 时间缩放绝不能永久卡在 0 —— 那会让整个游戏静止。
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() > _hitstop_until_msec + 50:
		Engine.time_scale = 1.0


## 顿帧：命中瞬间把时间几乎冻结，duration 按真实时间计算。
func hitstop(duration: float, scale: float = 0.02) -> void:
	var end_msec := Time.get_ticks_msec() + int(duration * 1000.0)
	if Engine.time_scale < 1.0 and end_msec <= _hitstop_until_msec:
		return  # 已经有更长的顿帧在进行中
	_hitstop_until_msec = end_msec
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	# 只有最后一次发起的顿帧负责恢复，避免互相踩
	if token == _hitstop_token:
		Engine.time_scale = 1.0


func shake(trauma: float) -> void:
	shake_requested.emit(trauma)


## 命中一次的完整反馈：顿帧 + 震屏 + 飘字
func hit_feedback(world_pos: Vector2, amount: int, is_crit: bool = false) -> void:
	spawn_damage_number(world_pos, amount, is_crit)
	hitstop(0.06 if is_crit else 0.04)
	shake(0.35 if is_crit else 0.2)


func spawn_damage_number(world_pos: Vector2, amount: int, is_crit: bool = false) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var number := DamageNumberScene.instantiate() as DamageNumber
	scene_root.add_child(number)
	number.global_position = world_pos
	number.setup(amount, is_crit)
