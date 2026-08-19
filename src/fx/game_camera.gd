extends Camera2D
## 跟随 + 震屏。trauma 平方衰减，命中时抖得凶、恢复得快。

@export var max_offset := Vector2(9, 6)
@export var decay := 2.2
@export var lookahead := 26.0  ## 朝向前方多看一点

var _trauma := 0.0
var _noise_t := 0.0
var _look := 0.0


func _ready() -> void:
	FX.shake_requested.connect(_on_shake_requested)
	make_current()


## 把镜头夹在房间范围内，别让玩家看到关卡外面的空白
func set_limits(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)
	reset_smoothing()


func _on_shake_requested(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _process(delta: float) -> void:
	var body := get_parent() as CharacterBody2D
	if body:
		var target := signf(body.velocity.x) * lookahead
		_look = lerpf(_look, target, 1.0 - exp(-3.0 * delta))

	# 顿帧期间 time_scale ≈ 0，但震屏要照常抖 —— 所以用不受时间缩放影响的 delta
	var udelta := delta / maxf(Engine.time_scale, 0.001)
	_trauma = maxf(_trauma - decay * udelta, 0.0)
	var shake := _trauma * _trauma
	_noise_t += udelta * 40.0
	offset = Vector2(
		_look + max_offset.x * shake * (randf() * 2.0 - 1.0),
		max_offset.y * shake * (randf() * 2.0 - 1.0)
	)
