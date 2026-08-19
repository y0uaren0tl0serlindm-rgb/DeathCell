extends Node
## Art-only integration check for the player roll presentation.

const MainScene := preload("res://src/main.tscn")
const ROLL_TEXTURE := "res://assets/characters/player/animations/deathcell_hero_roll_v1.png"
const IDLE_TEXTURE := "res://assets/characters/player/concepts/deathcell_hero_sprite_master_v2.png"

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

	_check(hero.texture.resource_path == IDLE_TEXTURE, "idle texture is active before roll")

	Input.action_press(&"roll")
	await _physics_frames(2)
	Input.action_release(&"roll")
	await get_tree().process_frame

	_check(int(player.get("state")) == 4, "player entered roll state")
	_check(hero.texture.resource_path == ROLL_TEXTURE, "roll pose texture is active")
	hero.call("_update_action_pose")
	var expected_center: Vector2 = player.global_position + Vector2(0, -11)
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

	await _physics_frames(30)
	await get_tree().process_frame
	_check(hero.texture.resource_path == IDLE_TEXTURE, "idle texture returns after roll")
	_finish()


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


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
