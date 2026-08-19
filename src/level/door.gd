extends Area2D
## 通往下一层的门。玩家进入范围后按 E 进入下一个房间。

@onready var prompt: Label = $Prompt
@onready var visual: Node2D = $Visual

var _player_inside := false
var _used := false


func _ready() -> void:
	prompt.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	visual.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
	if _player_inside and not _used and Input.is_action_just_pressed(&"interact"):
		_used = true
		prompt.visible = false
		Events.request_next_room.emit()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player_inside = true
		prompt.visible = not _used


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player_inside = false
		prompt.visible = false
