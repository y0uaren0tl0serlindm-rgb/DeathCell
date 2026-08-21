extends Sprite2D
## Presentation-only player animation adapter. Gameplay remains authoritative for
## velocity, collisions, state, and facing; this script only reads that data.

enum MovementVisual { IDLE, START, LOOP, STOP, TURN }

@export var idle_frame_01_texture: Texture2D
@export var idle_frame_02_texture: Texture2D
@export var idle_frame_03_texture: Texture2D
@export var idle_frame_04_texture: Texture2D
@export var idle_frame_05_texture: Texture2D
@export var idle_frame_06_texture: Texture2D
@export var idle_frame_07_texture: Texture2D
@export var idle_frame_08_texture: Texture2D
@export var roll_texture: Texture2D
@export var attack_a_frame_01_texture: Texture2D
@export var attack_a_frame_02_texture: Texture2D
@export var attack_a_frame_03_texture: Texture2D
@export var attack_a_frame_04_texture: Texture2D
@export var attack_a_frame_05_texture: Texture2D
@export var attack_a_frame_06_texture: Texture2D
@export var attack_b_frame_01_texture: Texture2D
@export var attack_b_frame_02_texture: Texture2D
@export var attack_b_frame_03_texture: Texture2D
@export var attack_b_frame_04_texture: Texture2D
@export var attack_b_frame_05_texture: Texture2D
@export var attack_b_frame_06_texture: Texture2D
@export var run_frame_01_texture: Texture2D
@export var run_frame_02_texture: Texture2D
@export var run_frame_03_texture: Texture2D
@export var run_frame_04_texture: Texture2D
@export var run_frame_05_texture: Texture2D
@export var run_frame_06_texture: Texture2D
@export var run_frame_07_texture: Texture2D
@export var run_frame_08_texture: Texture2D
@export var run_start_frame_01_texture: Texture2D
@export var run_start_frame_02_texture: Texture2D
@export var run_stop_frame_01_texture: Texture2D
@export var run_stop_frame_02_texture: Texture2D
@export var run_stop_frame_03_texture: Texture2D
@export var run_turn_frame_01_texture: Texture2D
@export var run_turn_frame_02_texture: Texture2D
@export var run_turn_frame_03_texture: Texture2D
@export var idle_state_value := 0
@export var run_state_value := 1
@export var roll_state_value := 4
@export var attack_state_value := 5
@export var idle_fps := 8.0
@export var run_fps := 14.0
@export var transition_fps := 18.0
@export var max_run_speed := 190.0
@export var turn_speed_threshold := 35.0
@export var idle_position := Vector2(0, -13)
@export var run_position := Vector2(0, -13)
@export var attack_position := Vector2(0, -13)
@export var roll_world_offset := Vector2(0, -13)
@export var idle_scale := Vector2(0.6, 0.6)
@export var run_scale := Vector2(0.6, 0.6)
@export var attack_scale := Vector2(0.6, 0.6)
@export var roll_scale := Vector2(0.6, 0.6)

var _host: Node
var _health: Node
var _movement_visual := MovementVisual.IDLE
var _movement_time := 0.0
var _visual_facing := 1
var _turn_from_facing := 1
var _turn_target_facing := -1

# The supplied sheets already contain their intended per-frame offsets inside one
# shared canvas. Keep the Sprite2D root stable and do not add a second bob.
const RUN_FRAME_Y_OFFSETS := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
const START_FRAME_Y_OFFSETS := [0.0, 0.0, 0.0]
const STOP_FRAME_Y_OFFSETS := [0.0, 0.0, 0.0]
const TURN_FRAME_Y_OFFSETS := [0.0, 0.0, 0.0]


func _ready() -> void:
	_host = get_parent().get_parent()
	_health = _host.get_node_or_null("Health")
	var host_facing: Variant = _host.get("facing")
	_visual_facing = int(host_facing) if host_facing != null else 1
	texture = idle_frame_01_texture
	position = idle_position
	scale = idle_scale
	flip_h = _visual_facing < 0


func _process(delta: float) -> void:
	if not is_instance_valid(_host):
		return

	_update_action_pose(delta)
	_update_feedback()


func _update_action_pose(delta := 0.0) -> void:
	var host_state: Variant = _host.get("state")
	var state_value := int(host_state) if host_state != null else idle_state_value
	var requested_facing := _read_host_facing()
	var velocity_x := _read_velocity_x()
	var input_x := _read_host_input_x()

	if state_value == roll_state_value:
		_show_roll(requested_facing)
		return

	_restore_parent_space()
	rotation = 0.0
	if state_value == attack_state_value:
		_enter_movement_visual(MovementVisual.IDLE)
		_visual_facing = requested_facing
		_show_attack()
		return

	# The gameplay state can briefly report IDLE while reversing direction or
	# pressing into a wall. Stop locomotion from released input instead of that
	# transient velocity state so START/STOP cannot restart every other frame.
	var continuing_requested_movement := (
		state_value == idle_state_value
		and absf(input_x) > 0.01
		and _movement_visual in [MovementVisual.START, MovementVisual.LOOP, MovementVisual.TURN]
	)
	if state_value == run_state_value or continuing_requested_movement:
		_update_running(delta, requested_facing, velocity_x)
	elif state_value == idle_state_value:
		_update_idle_or_stop(delta, requested_facing)
	else:
		_enter_movement_visual(MovementVisual.IDLE)
		_visual_facing = requested_facing
		_show_idle()


func _update_running(delta: float, requested_facing: int, velocity_x: float) -> void:
	if _movement_visual == MovementVisual.TURN:
		_movement_time += delta
		_show_turn()
		if _movement_time >= _frame_duration(3):
			_visual_facing = _turn_target_facing
			_enter_movement_visual(MovementVisual.START)
		return

	if requested_facing != _visual_facing:
		var velocity_direction := int(signf(velocity_x)) if absf(velocity_x) > turn_speed_threshold else requested_facing
		if velocity_direction == _visual_facing and absf(velocity_x) > turn_speed_threshold:
			_turn_from_facing = _visual_facing
			_turn_target_facing = requested_facing
			_enter_movement_visual(MovementVisual.TURN)
			_show_turn()
			return
		_visual_facing = requested_facing
		_enter_movement_visual(MovementVisual.START)

	if _movement_visual in [MovementVisual.IDLE, MovementVisual.STOP]:
		_enter_movement_visual(MovementVisual.START)
	else:
		_movement_time += delta

	if _movement_visual == MovementVisual.START:
		_show_start()
		if _movement_time >= _frame_duration(3):
			_enter_movement_visual(MovementVisual.LOOP)
	else:
		_show_run_loop(velocity_x)


func _update_idle_or_stop(delta: float, requested_facing: int) -> void:
	if _movement_visual in [MovementVisual.START, MovementVisual.LOOP, MovementVisual.TURN]:
		_visual_facing = requested_facing
		_enter_movement_visual(MovementVisual.STOP)
	elif _movement_visual == MovementVisual.STOP:
		_movement_time += delta

	if _movement_visual == MovementVisual.STOP:
		_show_stop()
		if _movement_time >= _frame_duration(3):
			_enter_movement_visual(MovementVisual.IDLE)
			_show_idle()
	else:
		_visual_facing = requested_facing
		_movement_time += delta
		_show_idle()


func _show_run_loop(velocity_x: float) -> void:
	var frames := _run_frames()
	var speed_ratio := absf(velocity_x) / maxf(max_run_speed, 1.0)
	var speed_scale := clampf(speed_ratio, 0.90, 1.05)
	var frame_index := int(_movement_time * run_fps * speed_scale) % frames.size()
	_show_movement_frame(frames[frame_index], RUN_FRAME_Y_OFFSETS[frame_index], _visual_facing < 0)


func _show_start() -> void:
	# The last startup pose is literally the first loop pose, matching the
	# reference project's shared seam frame instead of merely approximating it.
	var frames: Array[Texture2D] = [
		run_start_frame_01_texture,
		run_start_frame_02_texture,
		run_frame_01_texture,
	]
	var frame_index := mini(int(_movement_time * transition_fps), frames.size() - 1)
	_show_movement_frame(frames[frame_index], START_FRAME_Y_OFFSETS[frame_index], _visual_facing < 0)


func _show_stop() -> void:
	var frames: Array[Texture2D] = [
		run_stop_frame_01_texture,
		run_stop_frame_02_texture,
		run_stop_frame_03_texture,
	]
	var frame_index := mini(int(_movement_time * transition_fps), frames.size() - 1)
	_show_movement_frame(frames[frame_index], STOP_FRAME_Y_OFFSETS[frame_index], _visual_facing < 0)


func _show_turn() -> void:
	var frames: Array[Texture2D] = [
		run_turn_frame_01_texture,
		run_turn_frame_02_texture,
		run_turn_frame_03_texture,
	]
	var frame_index := mini(int(_movement_time * transition_fps), frames.size() - 1)
	# Frames are authored as right-to-left. Mirroring the whole transition handles
	# left-to-right while retaining the old facing until the final launch frame.
	_show_movement_frame(frames[frame_index], TURN_FRAME_Y_OFFSETS[frame_index], _turn_from_facing < 0)


func _show_movement_frame(frame: Texture2D, y_offset: float, mirrored: bool) -> void:
	if frame != null and texture != frame:
		texture = frame
	flip_h = mirrored
	position = run_position + Vector2(0.0, y_offset)
	scale = run_scale


func _show_idle() -> void:
	var frames := _idle_frames()
	var frame_index := int(_movement_time * idle_fps) % frames.size()
	if frames[frame_index] != null and texture != frames[frame_index]:
		texture = frames[frame_index]
	flip_h = _visual_facing < 0
	position = idle_position
	scale = idle_scale


## 这一段招式用哪套贴图，由 AttackStep.anim 直接给出。
## 不要退回 `_combo_index % 2` —— 段数和贴图数是各自变化的两个量，
## 取模只在两者相等时碰巧成立，锈剑三段配两套贴图时就播成了 A-B-A。
func attack_frames_for(anim: StringName) -> Array[Texture2D]:
	match anim:
		&"attack_b":
			return _attack_b_frames()
		_:
			return _attack_a_frames()


## 有贴图的攻击动画名。测试拿它核对每把武器的每一段都指向存在的动画。
static func attack_anim_names() -> Array[StringName]:
	return [&"attack_a", &"attack_b"]


func _show_attack() -> void:
	var active_step_for_anim: Variant = _host.get("_active_step")
	var anim := &"attack_a"
	if active_step_for_anim != null:
		var configured_anim: Variant = active_step_for_anim.get("anim")
		if configured_anim != null:
			anim = StringName(configured_anim)
	var frames := attack_frames_for(anim)
	var phase_value: Variant = _host.get("_attack_phase")
	var phase := int(phase_value) if phase_value != null else 0
	var phase_time_value: Variant = _host.get("_phase_time")
	var phase_time := float(phase_time_value) if phase_time_value != null else 0.0
	var frame_index := 0

	if phase == 0:
		# 前四帧是起手姿势，摊在整个前摇里；第五帧的斩击弧和第六帧的余韵
		# 分别正好占满判定与后摇 —— 三段时间片和这套贴图的三个节拍一一对应。
		var windup := 0.08
		if active_step_for_anim != null:
			var configured_windup: Variant = active_step_for_anim.get("windup")
			if configured_windup != null:
				windup = maxf(float(configured_windup), 0.001)
		frame_index = clampi(int((phase_time / windup) * 4.0), 0, 3)
	elif phase == 1:
		# The full slash belongs exactly to the gameplay hitbox's active window.
		frame_index = 4
	else:
		frame_index = 5

	if frames[frame_index] != null and texture != frames[frame_index]:
		texture = frames[frame_index]
	flip_h = _visual_facing < 0
	position = attack_position
	scale = attack_scale


func _show_roll(requested_facing: int) -> void:
	_enter_movement_visual(MovementVisual.IDLE)
	_visual_facing = requested_facing
	flip_h = requested_facing < 0
	if roll_texture != null and texture != roll_texture:
		texture = roll_texture
	if not is_set_as_top_level():
		set_as_top_level(true)
	scale = roll_scale
	global_position = _host.global_position + roll_world_offset
	global_rotation = get_parent().global_rotation


func _update_feedback() -> void:
	var flash_amount := 0.0
	var host_flash: Variant = _host.get("_flash")
	if host_flash != null and float(host_flash) > 0.0:
		flash_amount = 1.0
	var shader_material := material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter(&"flash_amount", flash_amount)

	var alpha := 1.0
	if is_instance_valid(_health):
		var invulnerable: Variant = _health.get("is_invulnerable")
		if invulnerable == true:
			alpha = 0.45 if int(Time.get_ticks_msec() / 50.0) % 2 == 0 else 1.0
	self_modulate.a = alpha


func _run_frames() -> Array[Texture2D]:
	# Preserve the exact eight-frame order of the supplied run sheet.
	return [
		run_frame_01_texture,
		run_frame_02_texture,
		run_frame_03_texture,
		run_frame_04_texture,
		run_frame_05_texture,
		run_frame_06_texture,
		run_frame_07_texture,
		run_frame_08_texture,
	]


func _idle_frames() -> Array[Texture2D]:
	return [
		idle_frame_01_texture,
		idle_frame_02_texture,
		idle_frame_03_texture,
		idle_frame_04_texture,
		idle_frame_05_texture,
		idle_frame_06_texture,
		idle_frame_07_texture,
		idle_frame_08_texture,
	]


func _attack_a_frames() -> Array[Texture2D]:
	return [
		attack_a_frame_01_texture,
		attack_a_frame_02_texture,
		attack_a_frame_03_texture,
		attack_a_frame_04_texture,
		attack_a_frame_05_texture,
		attack_a_frame_06_texture,
	]


func _attack_b_frames() -> Array[Texture2D]:
	return [
		attack_b_frame_01_texture,
		attack_b_frame_02_texture,
		attack_b_frame_03_texture,
		attack_b_frame_04_texture,
		attack_b_frame_05_texture,
		attack_b_frame_06_texture,
	]


func _read_host_facing() -> int:
	var host_facing: Variant = _host.get("facing")
	return int(host_facing) if host_facing != null else _visual_facing


func _read_velocity_x() -> float:
	if _host is CharacterBody2D:
		return (_host as CharacterBody2D).velocity.x
	return 0.0


func _read_host_input_x() -> float:
	var host_input: Variant = _host.get("_input_x")
	return float(host_input) if host_input != null else 0.0


func _frame_duration(frame_count: int) -> float:
	return float(frame_count) / maxf(transition_fps, 1.0)


func _enter_movement_visual(next_visual: MovementVisual) -> void:
	if _movement_visual == next_visual:
		return
	_movement_visual = next_visual
	_movement_time = 0.0


func _restore_parent_space() -> void:
	if is_set_as_top_level():
		set_as_top_level(false)
