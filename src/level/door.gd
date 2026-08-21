extends Area2D
## 房间出口。清完本层敌人后开放；L8 同一出口会表现为终点传送门。

@onready var prompt: Label = $Prompt
@onready var visual: Node2D = $Visual
@onready var frame: ColorRect = $Visual/Frame
@onready var glow: ColorRect = $Visual/Glow

var _player_inside := false
var _used := false
var _unlocked := false
var _is_final := false


func _ready() -> void:
	_is_final = Game.is_final_floor()
	prompt.visible = false
	if _is_final:
		frame.color = Color(0.22, 0.10, 0.32)
		glow.color = Color(0.78, 0.42, 1.0, 0.82)
	else:
		frame.color = Color(0.15, 0.13, 0.2)
		glow.color = Color(0.45, 0.95, 0.8, 0.75)
	Events.room_cleared.connect(_on_room_cleared)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * (0.006 if _is_final else 0.004))
	visual.modulate.a = pulse if _unlocked else 0.35
	if _is_final:
		var portal_scale := 1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.005)
		visual.scale = Vector2.ONE * portal_scale
		visual.rotation = 0.035 * sin(Time.get_ticks_msec() * 0.003)
	if _player_inside and _unlocked and not _used and Input.is_action_just_pressed(&"interact"):
		_used = true
		prompt.visible = false
		# Main 在这个唯一 seam 判断：L1~L7 换层，L8 通关。
		Events.request_next_room.emit()


func _on_room_cleared() -> void:
	_unlocked = true
	_update_prompt()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player_inside = true
		_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player_inside = false
		prompt.visible = false


func _update_prompt() -> void:
	if not _player_inside or _used:
		prompt.visible = false
		return
	prompt.visible = true
	if not _unlocked:
		prompt.text = "击败本层敌人"
	elif _is_final:
		prompt.text = "[E] 进入终点传送门"
	else:
		prompt.text = "[E] 下一层"
