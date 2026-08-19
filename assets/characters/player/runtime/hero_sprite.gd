extends Sprite2D
## Purely visual adapter for the player art.
## Reads presentation state from the host without changing gameplay behavior.

@export var idle_texture: Texture2D
@export var roll_texture: Texture2D
@export var roll_state_value := 4
@export var idle_position := Vector2(0, -12)
@export var roll_world_offset := Vector2(0, -11)
@export var idle_scale := Vector2(0.022, 0.022)
@export var roll_scale := Vector2(0.026, 0.026)

var _host: Node
var _health: Node


func _ready() -> void:
	_host = get_parent().get_parent()
	_health = _host.get_node_or_null("Health")
	texture = idle_texture
	position = idle_position
	scale = idle_scale


func _process(_delta: float) -> void:
	if not is_instance_valid(_host):
		return

	var host_facing: Variant = _host.get("facing")
	if host_facing != null:
		flip_h = int(host_facing) < 0

	_update_action_pose()

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


func _update_action_pose() -> void:
	var host_state: Variant = _host.get("state")
	var rolling := host_state != null and int(host_state) == roll_state_value

	if rolling:
		if roll_texture != null and texture != roll_texture:
			texture = roll_texture
		if not is_set_as_top_level():
			set_as_top_level(true)
		scale = roll_scale
		# The gameplay Visual node already calculates the 360-degree roll angle.
		# Temporarily ignore its foot-pivot transform, then copy only the angle so
		# the curled sprite spins around the center of the player's body.
		global_position = _host.global_position + roll_world_offset
		global_rotation = get_parent().global_rotation
	else:
		if idle_texture != null and texture != idle_texture:
			texture = idle_texture
		if is_set_as_top_level():
			set_as_top_level(false)
		position = idle_position
		rotation = 0.0
		scale = idle_scale
