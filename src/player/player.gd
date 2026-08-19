class_name Player
extends CharacterBody2D
## 玩家角色。手感参数全部集中在下面的常量区，调手感只需要动这里。
##
## 设计要点（照着死亡细胞的感觉来）：
##  - 输入缓冲 + 土狼时间：按早了/踩空了都还能跳，操作不会"吃键"
##  - 翻滚有无敌帧，并且能取消攻击后摇 —— 这是整套战斗节奏的发动机
##  - 攻击分 前摇/判定/后摇 三段，后摇过半即可被下一段或翻滚取消

enum State { IDLE, RUN, JUMP, FALL, ROLL, ATTACK, HURT, DEAD }
enum AttackPhase { WINDUP, ACTIVE, RECOVERY }

# --- 移动 ---
const RUN_SPEED := 190.0
const GROUND_ACCEL := 2400.0
const AIR_ACCEL := 1600.0
const GROUND_FRICTION := 2800.0
const AIR_FRICTION := 700.0
const GRAVITY := 1500.0
const MAX_FALL_SPEED := 700.0

# --- 跳跃 ---
const JUMP_VELOCITY := -395.0   ## 约 3 格半高
const JUMP_CUT_MULT := 0.42     ## 松开跳跃键时的减速（可变跳跃高度）
const COYOTE_TIME := 0.10
const JUMP_BUFFER_TIME := 0.12

# --- 翻滚 ---
const ROLL_SPEED := 330.0
const ROLL_TIME := 0.32
const ROLL_IFRAME_START := 0.04
const ROLL_IFRAME_END := 0.24
const ROLL_COOLDOWN := 0.15

# --- 受击 ---
const HURT_TIME := 0.18
const HURT_IFRAME := 0.6

const INPUT_BUFFER_TIME := 0.15

@onready var visual: Node2D = $Visual
@onready var body_rect: ColorRect = $Visual/Body
@onready var eye_rect: ColorRect = $Visual/Eye
@onready var blade_rect: ColorRect = $Visual/Blade
@onready var health: Health = $Health
@onready var hitbox: Hitbox = $AttackHitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var camera: Camera2D = $Camera2D

var state: State = State.FALL
var facing: int = 1

# 输入缓冲
var _jump_buffer := 0.0
var _attack_buffer := 0.0
var _roll_buffer := 0.0
var _coyote := 0.0
var _roll_cooldown := 0.0
var _input_x := 0.0
var _jump_held := false

# 状态计时
var _state_time := 0.0
var _hurt_dir := 1.0

# 武器 / 连招
var weapons: Array[WeaponData] = []
var weapon_index := 0
var weapon: WeaponData
var _combo_index := 0
var _combo_timer := 0.0          ## 距离上次攻击结束多久，超过 combo_window 连招重置
var _attack_phase: AttackPhase = AttackPhase.WINDUP
var _phase_time := 0.0
var _queued_attack := false      ## 后摇中已经预约了下一段
## 本次攻击锁定的武器与招式。攻击一旦开始就只认这两个，
## 中途换武器不会让伤害用旧武器、时间轴用新武器（issue #2）。
var _active_weapon: WeaponData
var _active_step: AttackStep
var _queued_swap := false        ## 攻击中按了换武器，等这次攻击结束再生效

# 表现
var _squash := Vector2.ONE
var _was_on_floor := true
var _flash := 0.0


func _ready() -> void:
	weapons = Weapons.all()
	weapon = weapons[weapon_index]
	health.invulnerable_time_on_hit = HURT_IFRAME
	health.changed.connect(func(c, m): Events.player_health_changed.emit(c, m))
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	Events.player_health_changed.emit(health.current, health.max_health)
	Events.player_weapon_changed.emit(weapon.display_name)


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_read_input()

	match state:
		State.IDLE, State.RUN, State.JUMP, State.FALL:
			_process_grounded_or_air(delta)
		State.ROLL:
			_process_roll(delta)
		State.ATTACK:
			_process_attack(delta)
		State.HURT:
			_process_hurt(delta)
		State.DEAD:
			_process_dead(delta)

	move_and_slide()
	_update_visual(delta)


# ---------------------------------------------------------------- 输入

func _tick_timers(delta: float) -> void:
	_state_time += delta
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_attack_buffer = maxf(_attack_buffer - delta, 0.0)
	_roll_buffer = maxf(_roll_buffer - delta, 0.0)
	_coyote = maxf(_coyote - delta, 0.0)
	_roll_cooldown = maxf(_roll_cooldown - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	if state != State.ATTACK:
		_combo_timer += delta
		if _combo_timer > weapon.combo_window:
			_combo_index = 0
			_active_weapon = null
			_active_step = null


func _read_input() -> void:
	if state == State.DEAD:
		_input_x = 0.0
		return
	_input_x = Input.get_axis(&"move_left", &"move_right")
	_jump_held = Input.is_action_pressed(&"jump")
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	if Input.is_action_just_pressed(&"attack"):
		_attack_buffer = INPUT_BUFFER_TIME
	if Input.is_action_just_pressed(&"roll"):
		_roll_buffer = INPUT_BUFFER_TIME
	# 松开跳跃键立刻截断上升速度 —— 可变跳跃高度
	if Input.is_action_just_released(&"jump") and velocity.y < -60.0:
		velocity.y *= JUMP_CUT_MULT
	if Input.is_action_just_pressed(&"swap_weapon"):
		# 攻击进行中不能立刻换 —— 排队到这次攻击结束再生效
		if state == State.ATTACK:
			_queued_swap = true
		else:
			_swap_weapon()


func _swap_weapon() -> void:
	_queued_swap = false
	weapon_index = (weapon_index + 1) % weapons.size()
	weapon = weapons[weapon_index]
	_combo_index = 0
	blade_rect.color = weapon.color
	Events.player_weapon_changed.emit(weapon.display_name)


# ---------------------------------------------------------------- 常规移动

func _process_grounded_or_air(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
	_apply_gravity(delta)
	_apply_horizontal(delta, _input_x, on_floor)

	if _input_x != 0.0:
		facing = int(signf(_input_x))

	# 跳跃（含土狼时间与输入缓冲）
	if _jump_buffer > 0.0 and _coyote > 0.0:
		_do_jump()
	if _roll_buffer > 0.0 and _roll_cooldown <= 0.0:
		_enter_roll()
		return
	if _attack_buffer > 0.0 and (on_floor or weapon.air_attack_allowed):
		_enter_attack(0 if _combo_timer > weapon.combo_window else _combo_index)
		return

	# 状态归类（只影响表现和后续判断）
	if on_floor:
		_set_state(State.RUN if absf(velocity.x) > 8.0 else State.IDLE)
	else:
		_set_state(State.JUMP if velocity.y < 0.0 else State.FALL)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	elif velocity.y > 0.0:
		velocity.y = 0.0


func _apply_horizontal(delta: float, dir: float, on_floor: bool) -> void:
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	var friction := GROUND_FRICTION if on_floor else AIR_FRICTION
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * RUN_SPEED, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _do_jump() -> void:
	velocity.y = JUMP_VELOCITY
	_jump_buffer = 0.0
	_coyote = 0.0
	_squash = Vector2(0.78, 1.25)
	_set_state(State.JUMP)


# ---------------------------------------------------------------- 翻滚

func _enter_roll() -> void:
	var was_attacking := state == State.ATTACK
	_set_state(State.ROLL)
	_state_time = 0.0
	_roll_buffer = 0.0
	hitbox.deactivate()
	if _input_x != 0.0:
		facing = int(signf(_input_x))
	velocity.x = facing * ROLL_SPEED
	_squash = Vector2(1.25, 0.75)
	if was_attacking:
		_apply_queued_swap()


func _process_roll(delta: float) -> void:
	_apply_gravity(delta)
	# 无敌帧只覆盖翻滚中段：起手和收招都能被打到
	var iframe := _state_time >= ROLL_IFRAME_START and _state_time <= ROLL_IFRAME_END
	if iframe and not health.is_invulnerable:
		health.start_iframes(ROLL_IFRAME_END - _state_time)
	elif not iframe and _state_time > ROLL_IFRAME_END and health.is_invulnerable:
		health.end_iframes()

	# 翻滚中保持速度，末段开始减速
	var t := _state_time / ROLL_TIME
	velocity.x = facing * ROLL_SPEED * (1.0 - 0.55 * maxf(t - 0.5, 0.0) * 2.0)

	if _state_time >= ROLL_TIME:
		_roll_cooldown = ROLL_COOLDOWN
		# 翻滚可以直接接攻击
		if _attack_buffer > 0.0:
			_enter_attack(_combo_index)
		else:
			_set_state(State.IDLE if is_on_floor() else State.FALL)


# ---------------------------------------------------------------- 攻击

func _enter_attack(index: int) -> void:
	_combo_index = index
	_set_state(State.ATTACK)
	_state_time = 0.0
	_phase_time = 0.0
	_attack_phase = AttackPhase.WINDUP
	_attack_buffer = 0.0
	_queued_attack = false

	if _input_x != 0.0:
		facing = int(signf(_input_x))

	_active_weapon = weapon
	_active_step = _active_weapon.step(_combo_index)
	var step := _active_step
	velocity.x = facing * step.lunge
	hitbox.damage = _active_weapon.damage_of(_combo_index)
	hitbox.crit_chance = _active_weapon.crit_chance
	hitbox.knockback_force = step.knockback
	hitbox.hitstop = step.hitstop
	hitbox.knockback_dir = Vector2(facing, -0.25).normalized()
	hitbox.configure_shape(Vector2(step.hitbox_offset.x * facing, step.hitbox_offset.y), step.hitbox_size)


func _process_attack(delta: float) -> void:
	_apply_gravity(delta)
	# 攻击中只有很弱的空中控制，地面则迅速刹车（出招要有"定身感"）
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * 0.7 * delta)
	else:
		velocity.x = move_toward(velocity.x, _input_x * RUN_SPEED * 0.6, AIR_ACCEL * 0.5 * delta)

	var step := _active_step
	_phase_time += delta

	match _attack_phase:
		AttackPhase.WINDUP:
			if _phase_time >= step.windup:
				_phase_time -= step.windup
				_attack_phase = AttackPhase.ACTIVE
				hitbox.activate()
		AttackPhase.ACTIVE:
			if _phase_time >= step.active:
				_phase_time -= step.active
				_attack_phase = AttackPhase.RECOVERY
				hitbox.deactivate()
		AttackPhase.RECOVERY:
			var cancellable := _phase_time >= step.recovery * step.cancel_after
			# 翻滚永远优先：它是取消后摇的万能手段
			if cancellable and _roll_buffer > 0.0 and _roll_cooldown <= 0.0:
				_enter_roll()
				return
			if _attack_buffer > 0.0:
				_queued_attack = true
				_attack_buffer = 0.0
			if cancellable and _queued_attack:
				_combo_timer = 0.0
				_enter_attack(_combo_index + 1)
				return
			if _phase_time >= step.recovery:
				_end_attack()


func _end_attack() -> void:
	hitbox.deactivate()
	_combo_timer = 0.0
	_combo_index += 1
	_set_state(State.IDLE if is_on_floor() else State.FALL)
	_apply_queued_swap()


## 攻击彻底结束（不是连招中途）后才真正换武器。
## 连招内部的取消接续仍算同一次攻击序列，保持用同一把武器。
func _apply_queued_swap() -> void:
	if _queued_swap:
		_swap_weapon()


# ---------------------------------------------------------------- 受击 / 死亡

func _on_damaged(info: DamageInfo) -> void:
	if state == State.DEAD:
		return
	_flash = 0.18
	hitbox.deactivate()
	_hurt_dir = signf(info.knockback.x) if info.knockback.x != 0.0 else -facing
	velocity = Vector2(_hurt_dir * 140.0, -160.0)
	_set_state(State.HURT)
	_state_time = 0.0
	FX.shake(0.5)
	_apply_queued_swap()


func _process_hurt(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * 0.5 * delta)
	if _state_time >= HURT_TIME:
		# 受击硬直结束后可以立刻翻滚脱身
		if _roll_buffer > 0.0 and _roll_cooldown <= 0.0:
			_enter_roll()
		else:
			_set_state(State.IDLE if is_on_floor() else State.FALL)


func _on_died() -> void:
	_set_state(State.DEAD)
	hitbox.deactivate()
	hurtbox.monitorable = false
	velocity = Vector2(-facing * 90.0, -220.0)
	FX.shake(0.9)
	Events.player_died.emit()


func _process_dead(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)


# ---------------------------------------------------------------- 表现

func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	_state_time = 0.0


func _update_visual(delta: float) -> void:
	# 落地压扁
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_squash = Vector2(1.3, 0.72)
	_was_on_floor = on_floor

	_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-16.0 * delta))
	visual.scale = _squash
	visual.rotation = deg_to_rad(360.0 * (_state_time / ROLL_TIME)) * facing if state == State.ROLL else 0.0

	eye_rect.position.x = 1.0 if facing > 0 else -5.0

	# 刀光：只在判定阶段显示
	var showing := state == State.ATTACK and _attack_phase == AttackPhase.ACTIVE and _active_step != null
	blade_rect.visible = showing
	if showing:
		var step := _active_step
		blade_rect.size = step.hitbox_size
		blade_rect.position = Vector2(
			step.hitbox_offset.x * facing - step.hitbox_size.x * 0.5,
			step.hitbox_offset.y - step.hitbox_size.y * 0.5
		)

	# 受击闪白 / 无敌闪烁
	if _flash > 0.0:
		body_rect.color = Color(1, 1, 1)
	elif health.is_invulnerable and state != State.ROLL:
		body_rect.color = Color(0.55, 0.75, 0.95, 0.5 if int(_state_time * 20.0) % 2 == 0 else 1.0)
	else:
		body_rect.color = Color(0.55, 0.75, 0.95)


func set_camera_limits(bounds: Rect2) -> void:
	camera.set_limits(bounds)


## 换房间时复位（保留血量与武器）
func reset_for_room(spawn: Vector2) -> void:
	global_position = spawn
	velocity = Vector2.ZERO
	_set_state(State.FALL)
	hitbox.deactivate()
	_combo_index = 0
