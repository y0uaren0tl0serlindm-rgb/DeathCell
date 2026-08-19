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
## 连招末段之后是否回到第一段。默认 false ——
## 以前 step() 用 index % size 隐式循环，导致持续点击就能无限续招、没有终点（issue #9）。
## 要循环必须在这里显式打开。
@export var loops: bool = false


## 这一段连招存不存在。末段之后没有下一段（除非显式开了 loops）。
func has_step(index: int) -> bool:
	if combo.is_empty() or index < 0:
		return false
	return loops or index < combo.size()


func step(index: int) -> AttackStep:
	if combo.is_empty():
		return AttackStep.new()
	if loops:
		return combo[index % combo.size()]
	return combo[clampi(index, 0, combo.size() - 1)]


func damage_of(index: int) -> int:
	return int(round(base_damage * step(index).damage_mult))
