extends CanvasLayer
## 局内 HUD。结算与选人由独立的 MetaScreen 负责。

const BAR_WIDTH := 140.0

@onready var health_fill: ColorRect = $Root/HealthBar/Fill
@onready var health_delayed: ColorRect = $Root/HealthBar/Delayed
@onready var health_label: Label = $Root/HealthBar/Value
@onready var cells_label: Label = $Root/CellsLabel
@onready var depth_label: Label = $Root/DepthLabel
@onready var weapon_label: Label = $Root/WeaponLabel


func _ready() -> void:
	Events.player_health_changed.connect(_on_health_changed)
	Events.cells_changed.connect(_on_cells_changed)
	Events.depth_changed.connect(_on_depth_changed)
	Events.player_weapon_changed.connect(_on_weapon_changed)


func _on_health_changed(current: int, maximum: int) -> void:
	var ratio := float(current) / float(maxi(maximum, 1))
	health_fill.size.x = BAR_WIDTH * ratio
	health_label.text = "%d / %d" % [current, maximum]
	# 拖尾条慢一拍收缩，直观看出刚刚掉了多少血。
	var tween := create_tween()
	tween.tween_interval(0.18)
	tween.tween_property(health_delayed, "size:x", BAR_WIDTH * ratio, 0.25)


func _on_cells_changed(amount: int) -> void:
	cells_label.text = "本局细胞 %d" % amount


func _on_depth_changed(depth: int) -> void:
	depth_label.text = "第 %d / %d 层" % [depth + 1, Game.TOTAL_FLOORS]


func _on_weapon_changed(weapon_name: String) -> void:
	weapon_label.text = weapon_name
