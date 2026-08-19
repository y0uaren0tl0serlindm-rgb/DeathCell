class_name DamageInfo
extends RefCounted
## 一次伤害的完整描述。攻击方创建，受击方消费。
##
## 用 _init 而不是静态工厂：静态工厂里要写 DamageInfo.new()，
## 那是在引用自己的 class_name，没有全局类缓存时解析不了（issue #8）。

var amount: int = 1
var knockback: Vector2 = Vector2.ZERO
var source: Node = null
var is_crit: bool = false
var hitstop: float = 0.04
var stun_time: float = 0.2


func _init(amount_: int = 1, knockback_: Vector2 = Vector2.ZERO, source_: Node = null) -> void:
	amount = amount_
	knockback = knockback_
	source = source_
