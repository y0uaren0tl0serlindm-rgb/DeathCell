extends Node
## Art-only integration check for jump, fall, roll, hurt, and death presentation.

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
const JUMP_TEXTURE := "res://assets/characters/player/animations/swordsman_jump_sheet.png"
const FALL_TEXTURE := "res://assets/characters/player/animations/swordsman_fall_sheet.png"
const ROLL_TEXTURE := "res://assets/characters/player/animations/swordsman_idle_01.png"
const HURT_TEXTURE := "res://assets/characters/player/animations/swordsman_hurt_sheet.png"
const DEATH_TEXTURE := "res://assets/characters/player/animations/swordsman_death_sheet.png"

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

	_check(_texture_source_path(hero.texture) in IDLE_TEXTURES, "existing eight-frame idle animation is active")
	_check(_distinct_frame_count(hero.call("_idle_frames")) == 8, "idle remains unchanged")
	_check(_distinct_frame_count(hero.call("_jump_frames")) == 2, "jump keeps both supplied frames")
	_check(_distinct_frame_count(hero.call("_fall_frames")) == 2, "fall keeps both supplied frames")
	_check(_distinct_frame_count(hero.call("_hurt_frames")) == 4, "hurt keeps all four supplied frames")
	_check(_distinct_frame_count(hero.call("_death_frames")) == 6, "death keeps all six supplied frames")

	Input.action_press(&"jump")
	await _wait_for_state(player, 2, 12)
	await get_tree().process_frame
	_check(int(player.get("state")) == 2, "player entered jump state")
	_check(_texture_source_path(hero.texture) == JUMP_TEXTURE, "jump sheet is active while rising")
	Input.action_release(&"jump")
	await _wait_for_state(player, 3, 60)
	_check(int(player.get("state")) == 3, "player entered fall state")
	_check(_texture_source_path(hero.texture) == FALL_TEXTURE, "fall sheet is active while descending")
	await _wait_until_grounded(player, 120)
	await _physics_frames(4)

	Input.action_press(&"roll")
	await _physics_frames(2)
	Input.action_release(&"roll")
	await get_tree().process_frame

	_check(int(player.get("state")) == 4, "player entered roll state")
	_check(_texture_source_path(hero.texture) == ROLL_TEXTURE, "existing roll presentation remains active")
	hero.call("_update_action_pose")
	var expected_center: Vector2 = player.global_position + Vector2(0, -13)
	print("    roll center actual=%s expected=%s local=%s parent_rotation=%.3f" % [
		hero.global_position, expected_center, hero.position, hero.get_parent().rotation
	])
	_check(hero.is_set_as_top_level(), "roll sprite uses an independent center pivot")
	_check(hero.global_position.distance_to(expected_center) < 0.75, "roll sprite rotates around body center")
	if OS.get_environment("DEATHCELL_CAPTURE_ROLL") == "1":
		await RenderingServer.frame_post_draw
		var capture := get_viewport().get_texture().get_image()
		var capture_path := "res://art/previews/runtime_roll_v1.png"
		var save_error := capture.save_png(ProjectSettings.globalize_path(capture_path))
		_check(save_error == OK, "roll preview capture saved")

	# Allow residual roll velocity to enter the presentation-only stop recovery
	# before requiring the final idle pose.
	await _physics_frames(60)
	await get_tree().process_frame
	_check(_texture_source_path(hero.texture) in IDLE_TEXTURES, "idle animation returns after roll")

	player.call("_set_state", 6)
	player.set("_state_time", 0.09)
	hero.call("_update_action_pose")
	_check(_texture_source_path(hero.texture) == HURT_TEXTURE, "hurt sheet is active in HURT state")

	player.call("_set_state", 7)
	player.set("_state_time", 5.0)
	hero.call("_update_action_pose")
	var death_frames: Array = hero.call("_death_frames")
	_check(_texture_source_path(hero.texture) == DEATH_TEXTURE, "death sheet is active in DEAD state")
	_check(hero.texture == death_frames[-1], "death animation holds on its final frame")
	_finish()


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _wait_for_state(player: Node, expected: int, max_frames: int) -> void:
	for i in max_frames:
		if int(player.get("state")) == expected:
			return
		await get_tree().physics_frame


func _wait_until_grounded(player: CharacterBody2D, max_frames: int) -> void:
	for i in max_frames:
		if player.is_on_floor():
			return
		await get_tree().physics_frame


func _texture_source_path(frame_texture: Texture2D) -> String:
	if frame_texture is AtlasTexture:
		var atlas_texture := frame_texture as AtlasTexture
		return atlas_texture.atlas.resource_path if atlas_texture.atlas else ""
	return frame_texture.resource_path if frame_texture else ""


func _distinct_frame_count(frames: Array) -> int:
	var ids := {}
	for frame in frames:
		if frame != null:
			ids[frame.get_instance_id()] = true
	return ids.size()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("\nRoll visual test passed")
	else:
		print("\nRoll visual test failed: %s" % ", ".join(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)
