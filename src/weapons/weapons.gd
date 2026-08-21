class_name Weapons
extends RefCounted
## 武器库。现在用代码定义，方便快速调数值；
## 定型之后可以在编辑器里另存为 .tres，交给策划/自己拖拽调整。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const AttackStep = preload("res://src/weapons/attack_step.gd")
const WeaponData = preload("res://src/weapons/weapon_data.gd")

## 现在有几套攻击动画就只能有几段连招 —— 见 AttackStep.anim。
## 加第三套贴图之前，任何武器的 combo 长度都不该超过 2。
const ANIM_A := &"attack_a"
const ANIM_B := &"attack_b"


static func _step(
	anim: StringName,
	windup: float, active: float, recovery: float,
	dmg: float, lunge: float, knock: float,
	offset: Vector2, size: Vector2, cancel_after: float = 0.45
) -> AttackStep:
	var s := AttackStep.new()
	s.anim = anim
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


## 玩家的固定武器（当前唯一一把）。
##
## 两段连招：横斩起手 → 下劈收尾。段数刻意等于现有攻击贴图数 ——
## 以前是三段配两套贴图，第三段只能复用第一段的动画，打出来像连招断了
## （旧的第二段本身也只是第一段的 1.1 倍复制品，删掉它没有损失）。
## 美术补出第三套斩击后，在这里加一段 ANIM_C 即可。
static func rusty_sword() -> WeaponData:
	var w := WeaponData.new()
	w.display_name = "锈剑"
	w.base_damage = 12
	w.crit_chance = 0.12
	w.color = Color(0.85, 0.9, 1.0)
	w.combo = [
		_step(ANIM_A, 0.06, 0.08, 0.16, 1.0, 80.0, 170.0, Vector2(15, -11), Vector2(26, 20)),
		_step(ANIM_B, 0.10, 0.10, 0.28, 1.6, 130.0, 360.0, Vector2(18, -11), Vector2(32, 24), 0.6),
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
		_step(ANIM_A, 0.04, 0.06, 0.10, 1.0, 60.0, 110.0, Vector2(12, -11), Vector2(20, 18), 0.3),
		_step(ANIM_B, 0.05, 0.07, 0.20, 1.5, 110.0, 260.0, Vector2(14, -11), Vector2(24, 20), 0.5),
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
		_step(ANIM_A, 0.20, 0.10, 0.34, 1.0, 70.0, 420.0, Vector2(18, -11), Vector2(34, 28), 0.7),
		_step(ANIM_B, 0.26, 0.12, 0.42, 1.4, 90.0, 520.0, Vector2(20, -11), Vector2(38, 32), 0.7),
	]
	w.combo_window = 0.7
	return w


## 武器库全表。玩家现在固定用锈剑（武器绑定角色），这里的另外两把
## 是给后续掉落/词条系统留的，同时也让 smoke_test 能一次性校验
## "每一把武器的每一段都指定了存在的动画"。
static func all() -> Array[WeaponData]:
	return [rusty_sword(), twin_daggers(), heavy_hammer()]
