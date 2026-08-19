extends CanvasLayer
## HUD + 死亡界面。只通过 Events 拿数据，不持有任何游戏对象引用。

const BAR_WIDTH := 140.0

@onready var health_fill: ColorRect = $Root/HealthBar/Fill
@onready var health_delayed: ColorRect = $Root/HealthBar/Delayed
@onready var health_label: Label = $Root/HealthBar/Value
@onready var cells_label: Label = $Root/CellsLabel
@onready var depth_label: Label = $Root/DepthLabel
@onready var weapon_label: Label = $Root/WeaponLabel
@onready var death_screen: Control = $DeathScreen
@onready var death_stats: Label = $DeathScreen/Stats


func _ready() -> void:
	death_screen.visible = false
	Events.player_health_changed.connect(_on_health_changed)
	Events.cells_changed.connect(_on_cells_changed)
	Events.depth_changed.connect(_on_depth_changed)
	Events.player_weapon_changed.connect(_on_weapon_changed)
	Events.player_died.connect(_on_player_died)
	Events.request_restart_run.connect(func(): death_screen.visible = false)


func _on_health_changed(current: int, maximum: int) -> void:
	var ratio := float(current) / float(maxi(maximum, 1))
	health_fill.size.x = BAR_WIDTH * ratio
	health_label.text = "%d / %d" % [current, maximum]
	# 拖尾条：慢一拍收缩，能直观看出"刚刚掉了多少血"
	var tween := create_tween()
	tween.tween_interval(0.18)
	tween.tween_property(health_delayed, "size:x", BAR_WIDTH * ratio, 0.25)


func _on_cells_changed(amount: int) -> void:
	cells_label.text = "细胞 %d" % amount


func _on_depth_changed(depth: int) -> void:
	depth_label.text = "第 %d 层" % (depth + 1)


func _on_weapon_changed(weapon_name: String) -> void:
	weapon_label.text = "%s   [K] 换武器" % weapon_name


func _on_player_died() -> void:
	death_stats.text = "深度 %d 层    细胞 %d\n\n[R] 重新开始" % [Game.depth + 1, Game.cells]
	await get_tree().create_timer(0.8, true, false, true).timeout
	death_screen.visible = true
