class_name DamageInfo
extends RefCounted
## 一次伤害的完整描述。攻击方创建，受击方消费。

var amount: int = 1
var knockback: Vector2 = Vector2.ZERO
var source: Node = null
var is_crit: bool = false
var hitstop: float = 0.04
var stun_time: float = 0.2


static func create(amount_: int, knockback_: Vector2, source_: Node) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount_
	d.knockback = knockback_
	d.source = source_
	return d
