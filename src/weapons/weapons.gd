class_name Weapons
extends RefCounted
## 武器库。现在用代码定义，方便快速调数值；
## 定型之后可以在编辑器里另存为 .tres，交给策划/自己拖拽调整。

static func _step(
	windup: float, active: float, recovery: float,
	dmg: float, lunge: float, knock: float,
	offset: Vector2, size: Vector2, cancel_after: float = 0.45
) -> AttackStep:
	var s := AttackStep.new()
	s.windup = windup
	s.active = active
	s.recovery = recovery
	s.damage_mult = dmg
	s.lunge = lunge
	s.knockback = knock
	s.hitbox_offset = offset
	s.hitbox_size = size
	s.cancel_after = cancel_after
	return s


## 均衡：三段连招，第三段伤害与击退明显更高
static func rusty_sword() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "锈剑"
	w.base_damage = 12
	w.crit_chance = 0.12
	w.color = Color(0.85, 0.9, 1.0)
	w.combo = [
		_step(0.06, 0.08, 0.16, 1.0, 80.0, 170.0, Vector2(15, -11), Vector2(26, 20)),
		_step(0.06, 0.08, 0.18, 1.1, 95.0, 190.0, Vector2(16, -11), Vector2(28, 22)),
		_step(0.12, 0.10, 0.30, 1.8, 140.0, 380.0, Vector2(19, -11), Vector2(34, 26), 0.6),
	]
	return w


## 快刀：出手极快、伤害低、暴击高，靠翻滚取消贴脸打
static func twin_daggers() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "双匕"
	w.base_damage = 7
	w.crit_chance = 0.3
	w.color = Color(1.0, 0.85, 0.6)
	w.combo = [
		_step(0.04, 0.06, 0.10, 1.0, 60.0, 110.0, Vector2(12, -11), Vector2(20, 18), 0.3),
		_step(0.04, 0.06, 0.10, 1.0, 60.0, 110.0, Vector2(12, -11), Vector2(20, 18), 0.3),
		_step(0.05, 0.07, 0.20, 1.5, 110.0, 260.0, Vector2(14, -11), Vector2(24, 20), 0.5),
	]
	w.combo_window = 0.45
	return w


## 重锤：慢、后摇长，但一击带走小怪
static func heavy_hammer() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "重锤"
	w.base_damage = 30
	w.crit_chance = 0.08
	w.color = Color(1.0, 0.6, 0.5)
	w.combo = [
		_step(0.20, 0.10, 0.34, 1.0, 70.0, 420.0, Vector2(18, -11), Vector2(34, 28), 0.7),
		_step(0.26, 0.12, 0.42, 1.4, 90.0, 520.0, Vector2(20, -11), Vector2(38, 32), 0.7),
	]
	w.combo_window = 0.7
	return w


static func all() -> Array[WeaponData]:
	return [rusty_sword(), twin_daggers(), heavy_hammer()]
