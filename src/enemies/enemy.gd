class_name Enemy
extends CharacterBody2D
## 敌人基类：巡逻 → 发现玩家追击 → 进入攻击距离出招。
## 攻击一定有明显前摇（变红 + 停住），这样玩家才有翻滚/走位的读招空间。

enum State { PATROL, CHASE, WINDUP, ATTACK, RECOVER, HURT, DEAD }

const GRAVITY := 1400.0
const MAX_FALL := 700.0

@export var move_speed := 55.0
@export var chase_speed := 95.0
@export var detect_range := 150.0
@export var attack_range := 30.0
@export var attack_windup := 0.42
@export var attack_active := 0.14
@export var attack_recover := 0.5
@export var attack_lunge := 170.0
@export var attack_damage := 12
@export var cell_reward := 3
@export var base_color := Color(0.85, 0.35, 0.4)

@onready var visual: Node2D = $Visual
@onready var body_rect: ColorRect = $Visual/Body
@onready var health: Health = $Health
@onready var hitbox: Hitbox = $AttackHitbox
@onready var floor_check: RayCast2D = $FloorCheck
@onready var wall_check: RayCast2D = $WallCheck
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var eye_rect: ColorRect = $Visual/Eye

var state: State = State.PATROL
var facing := -1
var player: Node2D = null

var _state_time := 0.0
var _flash := 0.0
var _squash := Vector2.ONE


func _ready() -> void:
	add_to_group(&"enemy")
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	hitbox.damage = attack_damage
	hitbox.deactivate()
	_scale_to_depth()


## 按当前深度提升血量与伤害
func _scale_to_depth() -> void:
	var s := Game.difficulty_scale()
	health.set_max_health(int(round(health.max_health * s)))
	attack_damage = int(round(attack_damage * s))
	hitbox.damage = attack_damage


func _physics_process(delta: float) -> void:
	_state_time += delta
	_flash = maxf(_flash - delta, 0.0)
	_acquire_player()

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	elif velocity.y > 0.0:
		velocity.y = 0.0

	match state:
		State.PATROL: _patrol(delta)
		State.CHASE: _chase(delta)
		State.WINDUP: _windup(delta)
		State.ATTACK: _attack(delta)
		State.RECOVER: _recover(delta)
		State.HURT: _hurt(delta)
		State.DEAD: _dead(delta)

	move_and_slide()
	_update_visual(delta)


func _acquire_player() -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player")


func _player_distance() -> float:
	if player == null:
		return INF
	return global_position.distance_to(player.global_position)


func _can_see_player() -> bool:
	if player == null:
		return false
	var d: Vector2 = player.global_position - global_position
	return absf(d.x) <= detect_range and absf(d.y) <= 60.0


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0


# ---------------------------------------------------------------- 各状态

func _patrol(delta: float) -> void:
	velocity.x = move_toward(velocity.x, facing * move_speed, 800.0 * delta)
	_update_probes()
	# 前面没地板（悬崖）或撞墙 → 转身
	if is_on_floor() and (not floor_check.is_colliding() or wall_check.is_colliding()):
		facing = -facing
		velocity.x = 0.0
	if _can_see_player():
		_set_state(State.CHASE)


func _chase(delta: float) -> void:
	if not _can_see_player():
		if _state_time > 1.2:
			_set_state(State.PATROL)
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		return

	var dir := signf(player.global_position.x - global_position.x)
	if dir != 0.0:
		facing = int(dir)
	_update_probes()

	# 快到悬崖边就停下，不自杀式追击
	var blocked := is_on_floor() and (not floor_check.is_colliding() or wall_check.is_colliding())
	if _player_distance() <= attack_range:
		velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
		_enter_windup()
	elif blocked:
		velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, facing * chase_speed, 900.0 * delta)


func _enter_windup() -> void:
	_set_state(State.WINDUP)
	velocity.x = 0.0
	hitbox.knockback_dir = Vector2(facing, -0.3).normalized()
	hitbox.configure_shape(Vector2(16 * facing, -10), Vector2(30, 22))


func _windup(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
	# 前摇最后阶段锁定朝向，给玩家绕背的机会
	if _state_time < attack_windup * 0.5 and player:
		var dir := signf(player.global_position.x - global_position.x)
		if dir != 0.0:
			facing = int(dir)
	if _state_time >= attack_windup:
		_set_state(State.ATTACK)
		hitbox.knockback_dir = Vector2(facing, -0.3).normalized()
		hitbox.configure_shape(Vector2(16 * facing, -10), Vector2(30, 22))
		hitbox.activate()
		velocity.x = facing * attack_lunge
		_squash = Vector2(1.25, 0.8)


func _attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	if _state_time >= attack_active:
		hitbox.deactivate()
		_set_state(State.RECOVER)


func _recover(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	if _state_time >= attack_recover:
		_set_state(State.CHASE)


func _hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
	if _state_time >= 0.22:
		_set_state(State.CHASE)


func _dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)


func _update_probes() -> void:
	floor_check.position.x = 10.0 * facing
	wall_check.target_position.x = 12.0 * facing
	floor_check.force_raycast_update()
	wall_check.force_raycast_update()


# ---------------------------------------------------------------- 受击 / 死亡

func _on_damaged(info: DamageInfo) -> void:
	if state == State.DEAD:
		return
	_flash = 0.12
	_squash = Vector2(0.75, 1.3)
	hitbox.deactivate()
	velocity = Vector2(info.knockback.x, minf(info.knockback.y, -60.0))
	# 被打断攻击：这让玩家的输出有意义
	_set_state(State.HURT)


func _on_died() -> void:
	_set_state(State.DEAD)
	hitbox.deactivate()
	hurtbox.monitorable = false
	set_collision_layer_value(3, false)
	Events.enemy_died.emit(global_position, cell_reward)
	FX.shake(0.4)
	var tween := create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, 0.25)
	tween.parallel().tween_property(visual, "scale", Vector2(1.4, 0.4), 0.25)
	tween.tween_callback(queue_free)


func _update_visual(delta: float) -> void:
	_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	if state != State.DEAD:
		visual.scale = _squash
	if _flash > 0.0:
		body_rect.color = Color(1, 1, 1)
	elif state == State.WINDUP:
		# 前摇高亮：这是玩家的读招信号
		var pulse := 0.5 + 0.5 * sin(_state_time * 34.0)
		body_rect.color = base_color.lerp(Color(1, 0.95, 0.5), 0.5 + 0.5 * pulse)
	else:
		body_rect.color = base_color
	eye_rect.position.x = 2.0 if facing > 0 else -6.0
