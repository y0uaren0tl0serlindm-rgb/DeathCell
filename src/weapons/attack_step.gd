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


func total_time() -> float:
	return windup + active + recovery
