extends Sprite2D
## Purely visual adapter for the player art.
## Reads presentation state from the host without changing gameplay behavior.

var _host: Node
var _health: Node


func _ready() -> void:
	_host = get_parent().get_parent()
	_health = _host.get_node_or_null("Health")


func _process(_delta: float) -> void:
	if not is_instance_valid(_host):
		return

	var host_facing: Variant = _host.get("facing")
	if host_facing != null:
		flip_h = int(host_facing) < 0

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
