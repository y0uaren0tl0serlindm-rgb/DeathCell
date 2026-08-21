class_name MetaScreen
extends CanvasLayer
## 结算、解锁、选人共用的局外单界面。
## 只消费 Game 提供的快照并发出玩家意图，不直接读写局外状态。

signal character_requested(character_id: String)
signal start_requested()

@onready var title_label: Label = $Root/Panel/Title
@onready var settlement_label: Label = $Root/Panel/Settlement
@onready var bank_label: Label = $Root/Panel/Bank
@onready var status_label: Label = $Root/Panel/Status
@onready var start_button: Button = $Root/Panel/StartButton

var _buttons: Dictionary = {}


func _ready() -> void:
	_buttons = {
		Game.CHARACTER_RUSTY_SWORD: $Root/Panel/Cards/RustyButton,
		Game.CHARACTER_TWIN_DAGGERS: $Root/Panel/Cards/DaggersButton,
		Game.CHARACTER_HEAVY_HAMMER: $Root/Panel/Cards/HammerButton,
	}
	for character_id in _buttons:
		var button: Button = _buttons[character_id]
		button.pressed.connect(_on_character_pressed.bind(character_id))
	start_button.pressed.connect(func(): start_requested.emit())
	visible = false


func show_screen(snapshot: Dictionary, settlement: Dictionary = {}, message: String = "") -> void:
	visible = true
	bank_label.text = "局外细胞  %d" % int(snapshot.get("meta_cells", 0))
	status_label.text = message
	_update_settlement(settlement)
	_update_characters(snapshot.get("characters", []))
	start_button.grab_focus.call_deferred()


func hide_screen() -> void:
	visible = false


func _update_settlement(settlement: Dictionary) -> void:
	if settlement.is_empty():
		title_label.text = "整 备 区"
		settlement_label.text = "选择本局角色；角色一经选定，本局途中不再更换。"
		return

	var victory := int(settlement.get("outcome", Game.RunOutcome.DEATH)) == Game.RunOutcome.VICTORY
	title_label.text = "成 功 脱 出" if victory else "本 局 结 束"
	var floor_reached := int(settlement.get("reached_floor", 1))
	var carried := int(settlement.get("carried_cells", 0))
	var bonus := int(settlement.get("bonus_cells", 0))
	if victory:
		settlement_label.text = (
			"抵达 L%d / L%d　带出 %d　通关奖励 %d　共入账 %d"
			% [floor_reached, Game.TOTAL_FLOORS, carried, bonus, carried + bonus]
		)
	else:
		settlement_label.text = (
			"抵达 L%d / L%d　带出细胞 %d（100%% 入账）"
			% [floor_reached, Game.TOTAL_FLOORS, carried]
		)


func _update_characters(characters: Array) -> void:
	var selected_name := "锈剑"
	for data_value in characters:
		var data: Dictionary = data_value
		var character_id: String = data["id"]
		var button: Button = _buttons.get(character_id)
		if button == null:
			continue
		var unlocked: bool = data["unlocked"]
		var selected: bool = data["selected"]
		var state_text: String
		if selected:
			state_text = "◆ 当前选择"
			selected_name = data["name"]
		elif unlocked:
			state_text = "已解锁 · 点击选择"
		elif not data["prerequisite_met"]:
			state_text = "尚未开放"
		else:
			state_text = "解锁 %d 细胞" % int(data["cost"])
		button.text = "%s\n%s\n%s" % [data["name"], data["style"], state_text]
		button.modulate = (
			Color(0.75, 1.0, 0.82) if selected
			else Color.WHITE if unlocked
			else Color(0.72, 0.72, 0.78)
		)
	start_button.text = "以 %s 开始新一局" % selected_name


func _on_character_pressed(character_id: String) -> void:
	character_requested.emit(character_id)
