class_name DamageNumber
extends Node2D
## 伤害飘字。顿帧期间也要照常飘，所以 tween 忽略 time_scale。

@onready var label: Label = $Label


func setup(amount: int, is_crit: bool) -> void:
	label.text = str(amount)
	label.modulate = Color(1.0, 0.85, 0.3) if is_crit else Color(1, 1, 1)
	scale = Vector2.ONE * (1.5 if is_crit else 1.0)

	var drift := Vector2(randf_range(-14.0, 14.0), -26.0)
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + drift, 0.55).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.55).set_delay(0.15)
	tween.chain().tween_callback(queue_free)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 100
