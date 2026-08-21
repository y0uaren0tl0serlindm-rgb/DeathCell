class_name AttackStep
extends Resource
## 连招中的一段。死亡细胞的手感核心就在这三个时间片的比例上：
##   windup（前摇，短）→ active（判定，很短）→ recovery（后摇，可被取消）

@export var windup: float = 0.08       ## 前摇：越短越"跟手"
@export var active: float = 0.08       ## 判定开启时长
@export var recovery: float = 0.18     ## 后摇
@export var cancel_after: float = 0.5  ## 后摇进行到这个比例后可被下一段/翻滚取消

@export var damage_mult: float = 1.0
@export var knockback: float = 200.0
@export var lunge: float = 90.0        ## 出招时向前的位移冲量
@export var hitbox_offset: Vector2 = Vector2(14, -11)
@export var hitbox_size: Vector2 = Vector2(26, 20)
@export var hitstop: float = 0.04

## 这一段用哪套攻击动画。**每段必须显式指定，不能由段号推**。
##
## 以前表现层用 `_combo_index % 2` 在两套贴图之间轮换，于是锈剑的三段连招
## 播成 A-B-A：第三下和第一下长得一模一样，读起来像连招断了重新起手。
## 段数和贴图数是两个会各自变化的量，取模只是碰巧在段数==贴图数时成立。
## 写成数据之后，"连招和动画对不上"这件事在加招式时就会被测试挡下来。
@export var anim: StringName = &"attack_a"


func total_time() -> float:
	return windup + active + recovery
