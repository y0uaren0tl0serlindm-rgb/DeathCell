class_name Player
extends CharacterBody2D
## 玩家角色。手感参数全部集中在下面的常量区，调手感只需要动这里。
##
## 设计要点（照着死亡细胞的感觉来）：
##  - 输入缓冲 + 土狼时间：按早了/踩空了都还能跳，操作不会"吃键"
##  - 翻滚有无敌帧，并且能取消攻击后摇 —— 这是整套战斗节奏的发动机
##  - 攻击分 前摇/判定/后摇 三段，后摇过半即可被下一段或翻滚取消

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const AttackStep = preload("res://src/weapons/attack_step.gd")
const DamageInfo = preload("res://src/core/damage_info.gd")
const Health = preload("res://src/core/health.gd")
const Hitbox = preload("res://src/core/hitbox.gd")
const Hurtbox = preload("res://src/core/hurtbox.gd")
const WeaponData = preload("res://src/weapons/weapon_data.gd")
const Weapons = preload("res://src/weapons/weapons.gd")

enum State { IDLE, RUN, JUMP, FALL, ROLL, ATTACK, HURT, DEAD }
enum AttackPhase { WINDUP, ACTIVE, RECOVERY }

## 攻击进行中按下的键存进这里，到取消点再兑现。
## 规则只有一条：**永远只留最后按的那一个**（issue #9）。
## 以前是两个各自独立的布尔预约位，谁也覆盖不了谁，
## 于是"想改主意"这件事做不到 —— 玩家感觉像卡在攻击动画里。
## MOVE 不产生动作，它的作用是把尚未开始的续击清掉。
enum Intent { NONE, MOVE, ATTACK, ROLL, JUMP }

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
## 武器绑定在角色身上，游戏中不能切换 —— 一个角色 = 一套连招 = 一套攻击动画。
## 换武器的输入（原来的 K 键）已经移除；要改装备走 equip()，
## 后续的掉落/词条系统也从那里进来。
var weapon: WeaponData
var _combo_index := 0
var _combo_timer := 0.0          ## 距离上次攻击结束多久，超过 combo_window 连招重置
var _attack_phase: AttackPhase = AttackPhase.WINDUP
var _phase_time := 0.0
var _pending_intent: Intent = Intent.NONE   ## 攻击中唯一的待执行意图
## 本次攻击锁定的武器与招式。攻击一旦开始就只认这两个，
## 中途换武器不会让伤害用旧武器、时间轴用新武器（issue #2）。
var _active_weapon: WeaponData
var _active_step: AttackStep

# 表现
var _squash := Vector2.ONE
var _was_on_floor := true
var _flash := 0.0


func _ready() -> void:
	weapon = Weapons.rusty_sword()
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

	# 攻击中的输入走"意图槽"，攻击外的走定时缓冲。
	# 分开的原因：定时缓冲会过期，而攻击的取消点可能远晚于缓冲时长
	# —— 重锤第一击的取消点在 0.54 秒，0.15 秒的翻滚缓冲早没了（issue #9）。
	# 意图槽不设过期，一直留到取消点。
	var attacking := state == State.ATTACK

	if Input.is_action_just_pressed(&"jump"):
		if attacking: _set_intent(Intent.JUMP)
		else: _jump_buffer = JUMP_BUFFER_TIME
	if Input.is_action_just_pressed(&"attack"):
		if attacking: _set_intent(Intent.ATTACK)
		else: _attack_buffer = INPUT_BUFFER_TIME
	if Input.is_action_just_pressed(&"roll"):
		if attacking: _set_intent(Intent.ROLL)
		else: _roll_buffer = INPUT_BUFFER_TIME
	# 新按下方向键 = 改主意了，把还没开始的续击清掉。
	# 用"刚按下"而不是"按住"：按住方向打连招是常规操作，不该被当成放弃续击。
	if attacking and (Input.is_action_just_pressed(&"move_left")
			or Input.is_action_just_pressed(&"move_right")):
		_set_intent(Intent.MOVE)

	# 松开跳跃键立刻截断上升速度 —— 可变跳跃高度
	if Input.is_action_just_released(&"jump") and velocity.y < -60.0:
		velocity.y *= JUMP_CUT_MULT


## 后按的覆盖先按的，槽里永远只有一个。
## 这里刻意不做优先级表：规则越简单，玩家越能预测"我最后按的那个会生效"。
func _set_intent(intent: Intent) -> void:
	_pending_intent = intent


## 换上另一把武器。玩家没有对应的输入 —— 这是给掉落/词条系统和测试用的。
##
## 攻击进行中调用不会影响这一击：伤害和时间轴走 _active_weapon / _active_step，
## 那两个字段在 _enter_attack() 时就锁定了（issue #2）。
## 新武器从下一次起手开始生效，连招计数也一并归零。
func equip(new_weapon: WeaponData) -> void:
	if new_weapon == null or new_weapon == weapon:
		return
	weapon = new_weapon
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
		_resolve_intent_after_attack()


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
	# 上一套连招已经打完时索引会越界，重新起一套
	if not weapon.has_step(index):
		index = 0
	_combo_index = index
	_set_state(State.ATTACK)
	_state_time = 0.0
	_phase_time = 0.0
	_attack_phase = AttackPhase.WINDUP
	_attack_buffer = 0.0
	_pending_intent = Intent.NONE

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

	# clear_transient_state() 可能在攻击途中被调用（换房间、外部重置），
	# 那之后就没有合法的招式数据了 —— 直接收招，别让状态机带着空指针跑。
	if _active_step == null:
		_end_attack()
		return
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
			if cancellable and _consume_intent_at_cancel_point():
				return
			if _phase_time >= step.recovery:
				_end_attack()


## 到了取消点，兑现槽里的那个意图。返回 true 表示已经转去别的状态。
##
## 只有翻滚和跳跃会真的截断后摇 —— 它们是"取消"。
## 移动不截断：当前这一击仍然打完，保留出招的承诺感，
## 它的作用只是让尚未开始的续击不再发生。
func _consume_intent_at_cancel_point() -> bool:
	match _pending_intent:
		Intent.ROLL:
			if _roll_cooldown <= 0.0:
				_pending_intent = Intent.NONE
				_enter_roll()
				return true
		Intent.JUMP:
			# 转成跳跃缓冲交给常规状态机，让它自己判断在不在地面
			_pending_intent = Intent.NONE
			_jump_buffer = JUMP_BUFFER_TIME
			_end_attack()
			return true
		Intent.ATTACK:
			if weapon.has_step(_combo_index + 1):
				_pending_intent = Intent.NONE
				_combo_timer = 0.0
				_enter_attack(_combo_index + 1)
				return true
			# 末段之后没有下一段：丢掉这个意图，让这次攻击正常收尾。
			# 想再打必须重新按 —— 连招要有终点（issue #9）。
			_pending_intent = Intent.NONE
	return false


func _end_attack() -> void:
	hitbox.deactivate()
	_combo_timer = 0.0
	_combo_index += 1
	_set_state(State.IDLE if is_on_floor() else State.FALL)
	_resolve_intent_after_attack()


## 攻击彻底结束时结算剩下的意图。
## 到这里还没兑现的只剩"没赶上取消点"的翻滚和跳跃 —— 转成常规输入缓冲，
## 交给下一帧的状态机自己判断能不能做。
func _resolve_intent_after_attack() -> void:
	var intent := _pending_intent
	_pending_intent = Intent.NONE
	match intent:
		Intent.ROLL:
			_roll_buffer = INPUT_BUFFER_TIME
		Intent.JUMP:
			_jump_buffer = JUMP_BUFFER_TIME


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
	_resolve_intent_after_attack()


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


## 清掉所有"只属于当前这一刻"的战斗上下文与输入队列。
##
## 这里是唯一的瞬时状态清单 —— 新增任何 _queued_* / _active_* / 缓冲计时器
## 都要加到这里，否则它会跨房间泄漏，在下一次攻击结束时莫名其妙地生效（issue #6）。
## 判断标准：这个字段描述的是"某次攻击/某次输入"，还是"这个角色是什么"？
## 前者进这里，后者（血量、当前武器、朝向）不进。
func clear_transient_state() -> void:
	# 攻击上下文
	hitbox.deactivate()
	_active_weapon = null
	_active_step = null
	_attack_phase = AttackPhase.WINDUP
	_phase_time = 0.0
	_combo_index = 0
	_combo_timer = 0.0
	# 排队的意图
	_pending_intent = Intent.NONE
	# 输入缓冲与冷却
	_jump_buffer = 0.0
	_attack_buffer = 0.0
	_roll_buffer = 0.0
	_coyote = 0.0
	_roll_cooldown = 0.0
	_input_x = 0.0
	_jump_held = false


## 换房间时复位。
## 保留：血量、当前已装备的武器、朝向 —— 这些是"角色的状态"。
## 丢弃：上一房间的攻击上下文和排队输入 —— 房间切换是一道明确的状态边界。
func reset_for_room(spawn: Vector2) -> void:
	global_position = spawn
	velocity = Vector2.ZERO
	_set_state(State.FALL)
	clear_transient_state()
