class_name Hitbox
extends Area2D
## 攻击判定框。默认关闭，攻击的 active 阶段由角色脚本打开。
## 一次挥击对同一个目标只结算一次（activate() 会清空命中表）。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const DamageInfo = preload("res://src/core/damage_info.gd")
const Hurtbox = preload("res://src/core/hurtbox.gd")

signal hit(hurtbox: Hurtbox)

@export var damage: int = 10
@export var knockback_force: float = 220.0
@export var crit_chance: float = 0.0
@export var hitstop: float = 0.04
@export var stun_time: float = 0.2

## 击退方向，一般由攻击者设成朝向；为 ZERO 时用 hitbox 指向目标的方向
var knockback_dir: Vector2 = Vector2.ZERO

var _already_hit: Array[int] = []
@onready var _shape: CollisionShape2D = get_node_or_null("CollisionShape2D")


func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)
	set_active(false)


## 开启判定（新的一次挥击）
func activate() -> void:
	_already_hit.clear()
	set_active(true)


func deactivate() -> void:
	set_active(false)


func set_active(value: bool) -> void:
	monitoring = value
	if _shape:
		_shape.set_deferred("disabled", not value)


## 改变判定框的位置与大小（不同连招段用不同的范围）
func configure_shape(offset: Vector2, size: Vector2) -> void:
	if _shape == null:
		return
	_shape.position = offset
	var rect := _shape.shape as RectangleShape2D
	if rect:
		# shape 可能是共享资源，复制一份避免影响其他实例
		if not rect.resource_local_to_scene:
			rect = rect.duplicate()
			_shape.shape = rect
		rect.size = size


func _on_area_entered(area: Area2D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox == null:
		return
	var id := hurtbox.get_instance_id()
	if id in _already_hit:
		return
	_already_hit.append(id)

	var dir := knockback_dir
	if dir == Vector2.ZERO:
		dir = (hurtbox.global_position - global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT

	var info := DamageInfo.new(damage, dir * knockback_force, owner)
	info.is_crit = randf() < crit_chance
	if info.is_crit:
		info.amount = int(round(info.amount * 1.8))
	info.hitstop = hitstop
	info.stun_time = stun_time

	hurtbox.take_hit(info)
	hit.emit(hurtbox)
