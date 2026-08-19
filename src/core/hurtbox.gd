class_name Hurtbox
extends Area2D
## 受击判定框。把伤害转交给同级的 Health 节点，并广播命中特效。

signal hurt(info: DamageInfo)

@export var health_path: NodePath = ^"../Health"
@export var show_hit_feedback: bool = true

var _health: Health


func _ready() -> void:
	monitoring = false   # 只被别人检测，自己不检测
	monitorable = true
	_health = get_node_or_null(health_path) as Health


func take_hit(info: DamageInfo) -> void:
	if _health and _health.is_invulnerable:
		return
	if show_hit_feedback:
		FX.hit_feedback(global_position, info.amount, info.is_crit)
	Events.hit_landed.emit(global_position, info.amount, info.is_crit)
	hurt.emit(info)
	if _health:
		_health.take_damage(info)
