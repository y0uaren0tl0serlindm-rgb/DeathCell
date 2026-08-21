extends Node
## 一次 run 与跨 run 进度的唯一状态源。
##
## Main 只负责按顺序编排场景；层数上限、结算、解锁和选人规则都收在这里，
## 地图生成只需要继续读取 depth / room_rng()，不必知道局外流程。

enum RunOutcome { NONE, DEATH, VICTORY }

const TOTAL_FLOORS := 8
const VICTORY_BONUS_CELLS := 20
const MAX_CELL_DROPS := 5
const SAVE_PATH := "user://deathcell_progress.cfg"

const CHARACTER_RUSTY_SWORD := "rusty_sword"
const CHARACTER_TWIN_DAGGERS := "twin_daggers"
const CHARACTER_HEAVY_HAMMER := "heavy_hammer"

## 解锁成本仍集中在这里，后续调经济时不需要动 UI。
## 双匕 12 = 清完 L1 的 4 个 Grunt；重锤 36 是第二阶段目标。
const CHARACTER_DEFINITIONS := [
	{
		"id": CHARACTER_RUSTY_SWORD,
		"name": "锈剑",
		"style": "均衡 · 中距离两段连招",
		"cost": 0,
		"requires": "",
	},
	{
		"id": CHARACTER_TWIN_DAGGERS,
		"name": "双匕",
		"style": "贴身 · 快速取消与缠斗",
		"cost": 12,
		"requires": CHARACTER_RUSTY_SWORD,
	},
	{
		"id": CHARACTER_HEAVY_HAMMER,
		"name": "重锤",
		"style": "远距 · 预判与重击",
		"cost": 36,
		"requires": CHARACTER_TWIN_DAGGERS,
	},
]

# --- 本局状态 ---
var cells: int = 0
var depth: int = 0                 ## 0-based：L1 = 0，L8 = 7
var run_seed: int = 0
var rng := RandomNumberGenerator.new()
var run_active := false
var current_character_id := CHARACTER_RUSTY_SWORD

# --- 局外状态 ---
var meta_cells := 0
var unlocked_character_ids: Array[String] = [CHARACTER_RUSTY_SWORD]
var selected_character_id := CHARACTER_RUSTY_SWORD
var finished_runs := 0
var last_settlement: Dictionary = {}

## 保留旧字段，后续图纸系统可以继续从这里扩展。
var meta_blueprints: Array[String] = []

var _persistence_enabled := true


func _ready() -> void:
	_load_meta_progress()


## 把击杀奖励拆成若干颗掉落物。余数要摊到前几颗上 ——
## 直接整除会把 8 拆成 5 颗 ×1 = 5，凭空吞掉 3 个细胞（issue #5）。
static func split_cell_reward(reward: int, max_drops: int = MAX_CELL_DROPS) -> PackedInt32Array:
	var out := PackedInt32Array()
	if reward <= 0:
		return out
	var drops := clampi(reward, 1, maxi(max_drops, 1))
	var base := reward / drops
	var remainder := reward % drops
	for i in drops:
		out.append(base + (1 if i < remainder else 0))
	return out


## 没完成过任何一局时直接进入锈剑教学局；之后启动游戏先到局外界面。
func needs_first_run() -> bool:
	return finished_runs == 0


func start_new_run(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else randi()
	rng.seed = run_seed
	cells = 0
	depth = 0
	run_active = true
	last_settlement = {}
	current_character_id = CHARACTER_RUSTY_SWORD if needs_first_run() else selected_character_id
	Events.cells_changed.emit(cells)
	Events.depth_changed.emit(depth)


func add_cells(amount: int) -> void:
	if not run_active or amount <= 0:
		return
	cells += amount
	Events.cells_changed.emit(cells)


func spend_cells(amount: int) -> bool:
	if amount < 0 or cells < amount:
		return false
	cells -= amount
	Events.cells_changed.emit(cells)
	return true


## 结算只能成功一次。死亡和通关都把本局细胞 100% 存入局外账户，
## 通关额外给固定奖励；返回值是 UI 展示所需的完整快照。
func finish_run(outcome: int) -> Dictionary:
	if not run_active:
		return last_settlement.duplicate(true)
	if outcome != RunOutcome.DEATH and outcome != RunOutcome.VICTORY:
		push_error("finish_run() 收到非法结算类型：%d" % outcome)
		return {}

	var carried := cells
	var bonus := VICTORY_BONUS_CELLS if outcome == RunOutcome.VICTORY else 0
	var deposited := carried + bonus
	meta_cells += deposited
	finished_runs += 1
	run_active = false
	cells = 0
	last_settlement = {
		"outcome": outcome,
		"reached_floor": clampi(depth + 1, 1, TOTAL_FLOORS),
		"carried_cells": carried,
		"bonus_cells": bonus,
		"deposited_cells": deposited,
	}
	Events.cells_changed.emit(cells)
	_save_meta_progress()
	return last_settlement.duplicate(true)


func is_final_floor() -> bool:
	return depth >= TOTAL_FLOORS - 1


## 推进到下一层。只应该由 Main 这个流程协调者调用。
## 到了 L8 返回 false，不允许产生不存在的第 9 层。
func advance_depth() -> bool:
	if not run_active or is_final_floor():
		return false
	depth += 1
	Events.depth_changed.emit(depth)
	return true


## 每个房间用独立 RNG，保证同一个 seed + depth 永远生成同一个房间。
func room_rng() -> RandomNumberGenerator:
	var room_random := RandomNumberGenerator.new()
	room_random.seed = hash(str(run_seed) + "_" + str(depth))
	return room_random


## 随深度提升的敌人强度曲线。
func difficulty_scale() -> float:
	return 1.0 + depth * 0.18


## UI 只消费这份快照，不需要了解存档格式或解锁顺序。
func meta_snapshot() -> Dictionary:
	var characters: Array[Dictionary] = []
	for definition in CHARACTER_DEFINITIONS:
		var item: Dictionary = definition.duplicate(true)
		var character_id: String = item["id"]
		var required_id: String = item["requires"]
		item["unlocked"] = character_id in unlocked_character_ids
		item["selected"] = character_id == selected_character_id
		item["prerequisite_met"] = required_id.is_empty() or required_id in unlocked_character_ids
		characters.append(item)
	return {
		"meta_cells": meta_cells,
		"finished_runs": finished_runs,
		"selected_character_id": selected_character_id,
		"characters": characters,
	}


## 尝试解锁并返回适合直接展示给玩家的结果。
func unlock_character(character_id: String) -> Dictionary:
	var definition := _character_definition(character_id)
	if definition.is_empty():
		return {"ok": false, "message": "未知角色"}
	if character_id in unlocked_character_ids:
		return {"ok": true, "message": "%s 已经解锁" % definition["name"]}

	var required_id: String = definition["requires"]
	if not required_id.is_empty() and required_id not in unlocked_character_ids:
		var required := _character_definition(required_id)
		return {"ok": false, "message": "请先解锁 %s" % required.get("name", "前置角色")}

	var cost: int = definition["cost"]
	if meta_cells < cost:
		return {"ok": false, "message": "细胞不足：还差 %d" % (cost - meta_cells)}

	meta_cells -= cost
	unlocked_character_ids.append(character_id)
	_save_meta_progress()
	return {"ok": true, "message": "已解锁 %s" % definition["name"]}


func select_character(character_id: String) -> bool:
	if character_id not in unlocked_character_ids:
		return false
	selected_character_id = character_id
	_save_meta_progress()
	return true


## 点击角色卡的完整语义：未解锁则先消费细胞解锁，成功后直接选中。
func choose_character(character_id: String) -> Dictionary:
	var definition := _character_definition(character_id)
	if definition.is_empty():
		return {"ok": false, "message": "未知角色"}
	var was_locked := character_id not in unlocked_character_ids
	if was_locked:
		var unlock_result := unlock_character(character_id)
		if not unlock_result["ok"]:
			return unlock_result
	select_character(character_id)
	return {
		"ok": true,
		"message": ("已解锁并选择 %s" if was_locked else "已选择 %s") % definition["name"],
	}


func _character_definition(character_id: String) -> Dictionary:
	for definition in CHARACTER_DEFINITIONS:
		if definition["id"] == character_id:
			return definition
	return {}


func _save_meta_progress() -> void:
	if not _persistence_enabled:
		return
	var config := ConfigFile.new()
	config.set_value("meta", "cells", meta_cells)
	config.set_value("meta", "unlocked_characters", PackedStringArray(unlocked_character_ids))
	config.set_value("meta", "selected_character", selected_character_id)
	config.set_value("meta", "finished_runs", finished_runs)
	config.set_value("meta", "blueprints", PackedStringArray(meta_blueprints))
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("局外进度保存失败：%s" % error_string(error))


func _load_meta_progress() -> void:
	_reset_meta_fields()
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		push_warning("局外进度读取失败：%s" % error_string(error))
		return

	meta_cells = maxi(int(config.get_value("meta", "cells", 0)), 0)
	finished_runs = maxi(int(config.get_value("meta", "finished_runs", 0)), 0)

	var loaded_unlocks: PackedStringArray = config.get_value(
		"meta", "unlocked_characters", PackedStringArray([CHARACTER_RUSTY_SWORD]))
	unlocked_character_ids.clear()
	for character_id in loaded_unlocks:
		if not _character_definition(character_id).is_empty() and character_id not in unlocked_character_ids:
			unlocked_character_ids.append(character_id)
	if CHARACTER_RUSTY_SWORD not in unlocked_character_ids:
		unlocked_character_ids.push_front(CHARACTER_RUSTY_SWORD)

	selected_character_id = str(config.get_value(
		"meta", "selected_character", CHARACTER_RUSTY_SWORD))
	if selected_character_id not in unlocked_character_ids:
		selected_character_id = CHARACTER_RUSTY_SWORD

	var loaded_blueprints: PackedStringArray = config.get_value(
		"meta", "blueprints", PackedStringArray())
	meta_blueprints.assign(loaded_blueprints)


func _reset_meta_fields() -> void:
	meta_cells = 0
	unlocked_character_ids.assign([CHARACTER_RUSTY_SWORD])
	selected_character_id = CHARACTER_RUSTY_SWORD
	finished_runs = 0
	last_settlement = {}
	run_active = false
	cells = 0
	depth = 0
	current_character_id = CHARACTER_RUSTY_SWORD
	meta_blueprints.clear()


## 测试进程使用内存进度，既不读取也不覆盖玩家自己的 user:// 存档。
func begin_test_session() -> void:
	_persistence_enabled = false
	_reset_meta_fields()
