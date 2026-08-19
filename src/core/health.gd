class_name Health
extends Node
## 生命值容器。谁受伤都用它，玩家和敌人共用。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const DamageInfo = preload("res://src/core/damage_info.gd")

signal changed(current: int, maximum: int)
signal damaged(info: DamageInfo)
signal died()

@export var max_health: int = 100
@export var invulnerable_time_on_hit: float = 0.0  ## 受击后无敌时间（玩家 > 0，敌人一般 0）

var current: int
var is_invulnerable: bool = false
var is_dead: bool = false

var _iframe_timer: float = 0.0


func _ready() -> void:
	current = max_health


func _process(delta: float) -> void:
	if _iframe_timer > 0.0:
		_iframe_timer -= delta
		if _iframe_timer <= 0.0:
			is_invulnerable = false


func set_max_health(value: int, heal_to_full: bool = true) -> void:
	max_health = value
	if heal_to_full:
		current = max_health
	else:
		current = mini(current, max_health)
	changed.emit(current, max_health)


func take_damage(info: DamageInfo) -> void:
	if is_dead or is_invulnerable:
		return
	current = maxi(current - info.amount, 0)
	changed.emit(current, max_health)
	damaged.emit(info)
	if invulnerable_time_on_hit > 0.0:
		start_iframes(invulnerable_time_on_hit)
	if current == 0:
		is_dead = true
		died.emit()


func heal(amount: int) -> void:
	if is_dead:
		return
	current = mini(current + amount, max_health)
	changed.emit(current, max_health)


func start_iframes(duration: float) -> void:
	is_invulnerable = true
	_iframe_timer = maxf(_iframe_timer, duration)


func end_iframes() -> void:
	is_invulnerable = false
	_iframe_timer = 0.0


func ratio() -> float:
	return float(current) / float(max_health) if max_health > 0 else 0.0
