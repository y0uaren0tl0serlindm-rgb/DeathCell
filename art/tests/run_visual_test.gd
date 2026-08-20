extends Node
## Art-only integration check for start, loop, stop, and brake-turn movement.

const MainScene := preload("res://src/main.tscn")
const IDLE_TEXTURES := [
	"res://assets/characters/player/animations/swordsman_idle_01.png",
	"res://assets/characters/player/animations/swordsman_idle_02.png",
	"res://assets/characters/player/animations/swordsman_idle_03.png",
	"res://assets/characters/player/animations/swordsman_idle_04.png",
	"res://assets/characters/player/animations/swordsman_idle_05.png",
	"res://assets/characters/player/animations/swordsman_idle_06.png",
	"res://assets/characters/player/animations/swordsman_idle_07.png",
	"res://assets/characters/player/animations/swordsman_idle_08.png",
]
const RUN_TEXTURES := [
	"res://assets/characters/player/animations/swordsman_run_01.png",
	"res://assets/characters/player/animations/swordsman_run_02.png",
	"res://assets/characters/player/animations/swordsman_run_03.png",
	"res://assets/characters/player/animations/swordsman_run_04.png",
	"res://assets/characters/player/animations/swordsman_run_05.png",
	"res://assets/characters/player/animations/swordsman_run_06.png",
	"res://assets/characters/player/animations/swordsman_run_07.png",
	"res://assets/characters/player/animations/swordsman_run_08.png",
]
const START_TEXTURES := [
	"res://assets/characters/player/animations/swordsman_idle_01.png",
	"res://assets/characters/player/animations/swordsman_run_08.png",
	"res://assets/characters/player/animations/swordsman_run_01.png",
]
const STOP_TEXTURES := [
	"res://assets/characters/player/animations/swordsman_run_08.png",
	"res://assets/characters/player/animations/swordsman_idle_02.png",
	"res://assets/characters/player/animations/swordsman_idle_01.png",
]
const TURN_TEXTURES := [
	"res://assets/characters/player/animations/swordsman_run_01.png",
	"res://assets/characters/player/animations/swordsman_idle_01.png",
]

var _failures: Array[String] = []


func _ready() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await _physics_frames(35)

	var player := get_tree().get_first_node_in_group(&"player")
	var hero := player.get_node_or_null("Visual/HeroSprite") as Sprite2D if player else null
	_check(hero != null, "player art sprite exists")
	if hero == null:
		_finish()
		return

	_check(_texture_source_path(hero.texture) in IDLE_TEXTURES, "idle animation is active before running")
	var safe_position: Vector2 = player.position
	var observed_idle: Dictionary[String, bool] = {}
	var idle_scales: Dictionary[Vector2, bool] = {}
	var idle_positions: Dictionary[Vector2, bool] = {}
	for i in 80:
		hero.call("_update_action_pose", 1.0 / 60.0)
		await get_tree().process_frame
		observed_idle[_texture_source_path(hero.texture)] = true
		idle_scales[hero.scale] = true
		idle_positions[hero.position] = true
	_check_all_observed(IDLE_TEXTURES, observed_idle, "idle loop")
	_check(idle_scales.size() == 1 and idle_scales.has(Vector2(0.6, 0.6)), "idle keeps one display size: %s" % [idle_scales.keys()])
	_check(idle_positions.size() == 1 and idle_positions.has(Vector2(0, -13)), "idle keeps one grounded anchor: %s" % [idle_positions.keys()])

	var observed_start: Dictionary[String, bool] = {}
	Input.action_press(&"move_right")
	for i in 28:
		# Keep the player in a deterministic, obstacle-free run while the longer
		# shared-seam startup completes.
		player.position = safe_position
		player.velocity.x = 190.0
		await get_tree().physics_frame
		await get_tree().process_frame
		observed_start[_texture_source_path(hero.texture)] = true
	_check(int(player.get("state")) == 1, "player entered run state")
	_check(not hero.is_set_as_top_level(), "movement sprite remains in normal parent space")
	_check(hero.get_node_or_null("RunRig") == null, "movement uses complete frames without a joint rig")
	_check_all_observed(START_TEXTURES, observed_start, "run start")

	var observed_run: Dictionary[String, bool] = {}
	var observed_y: Dictionary[float, bool] = {}
	for i in 60:
		# Keep the isolated art test away from room walls/enemies while allowing
		# enough time to observe the full loop at gameplay speed.
		player.position = safe_position
		player.velocity.x = 190.0
		await get_tree().physics_frame
		await get_tree().process_frame
		observed_run[_texture_source_path(hero.texture)] = true
		if _texture_source_path(hero.texture) in RUN_TEXTURES:
			observed_y[hero.position.y] = true
	_check_all_observed(RUN_TEXTURES, observed_run, "run loop")
	_check(observed_y.size() == 1 and observed_y.has(-13.0), "run loop keeps one stable presentation anchor: %s" % [observed_y.keys()])

	var observed_turn: Dictionary[String, bool] = {}
	Input.action_release(&"move_right")
	Input.action_press(&"move_left")
	for i in 28:
		player.position = safe_position
		await get_tree().physics_frame
		await get_tree().process_frame
		observed_turn[_texture_source_path(hero.texture)] = true
	_check_all_observed(TURN_TEXTURES, observed_turn, "brake turn")
	_check(hero.flip_h, "visual completes the turn toward screen-left")

	for i in 70:
		player.position = safe_position
		player.velocity.x = -190.0
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(_texture_source_path(hero.texture) in RUN_TEXTURES, "run loop resumes after the turn: %s" % _texture_source_path(hero.texture))
	_check(hero.flip_h, "leftward run loop remains mirrored")

	var observed_stop: Dictionary[String, bool] = {}
	Input.action_release(&"move_left")
	for i in 35:
		player.position = safe_position
		await get_tree().physics_frame
		await get_tree().process_frame
		observed_stop[_texture_source_path(hero.texture)] = true
	_check_all_observed(STOP_TEXTURES, observed_stop, "run stop")
	_check(_texture_source_path(hero.texture) in IDLE_TEXTURES, "idle animation returns after stop recovery")
	_finish()


func _check_all_observed(expected: Array, observed: Dictionary[String, bool], label: String) -> void:
	for path in expected:
		_check(observed.has(path), "%s displays %s" % [label, path.get_file()])


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _texture_source_path(frame_texture: Texture2D) -> String:
	if frame_texture is AtlasTexture:
		var atlas_texture := frame_texture as AtlasTexture
		return atlas_texture.atlas.resource_path if atlas_texture.atlas else ""
	return frame_texture.resource_path if frame_texture else ""


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _finish() -> void:
	Input.action_release(&"move_right")
	Input.action_release(&"move_left")
	if _failures.is_empty():
		print("\nMovement visual test passed")
	else:
		print("\nMovement visual test failed: %s" % ", ".join(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)
