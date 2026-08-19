class_name WeaponData
extends Resource
## 一把武器 = 一组连招 + 一组数值。换武器就是换这个 Resource。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const AttackStep = preload("res://src/weapons/attack_step.gd")

@export var display_name: String = "断剑"
@export var base_damage: int = 12
@export var crit_chance: float = 0.1
@export var combo: Array[AttackStep] = []
@export var combo_window: float = 0.55   ## 上一段结束后多久内按攻击算接续连招
@export var color: Color = Color(0.9, 0.9, 1.0)
@export var air_attack_allowed: bool = true


func step(index: int) -> AttackStep:
	if combo.is_empty():
		return AttackStep.new()
	return combo[index % combo.size()]


func damage_of(index: int) -> int:
	return int(round(base_damage * step(index).damage_mult))
