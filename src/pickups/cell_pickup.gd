class_name CellPickup
extends Area2D
## 细胞掉落：先弹出去，短暂延迟后自动吸向玩家。

const GRAVITY := 900.0
const HOME_DELAY := 0.35
const HOME_ACCEL := 1600.0
const MAX_HOME_SPEED := 420.0

var value: int = 1
var velocity: Vector2 = Vector2.ZERO

var _age := 0.0
var _player: Node2D = null

@onready var visual: Node2D = $Visual


func setup(amount: int, initial_velocity: Vector2) -> void:
	value = amount
	velocity = initial_velocity


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age < HOME_DELAY:
		velocity.y += GRAVITY * delta
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	else:
		if _player == null or not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group(&"player")
		if _player:
			var dir := (_player.global_position + Vector2(0, -11) - global_position).normalized()
			velocity = velocity.move_toward(dir * MAX_HOME_SPEED, HOME_ACCEL * delta)
		else:
			velocity.y += GRAVITY * delta
	global_position += velocity * delta

	visual.scale = Vector2.ONE * (1.0 + 0.18 * sin(_age * 12.0))


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		Game.add_cells(value)
		queue_free()
