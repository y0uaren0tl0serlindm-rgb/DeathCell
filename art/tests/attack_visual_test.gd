extends Node
## Art-only integration check for the two alternating player attack actions.

const MainScene := preload("res://src/main.tscn")
const ATTACK_A := [
	"res://assets/characters/player/animations/swordsman_attack_a_01.png",
	"res://assets/characters/player/animations/swordsman_attack_a_02.png",
	"res://assets/characters/player/animations/swordsman_attack_a_03.png",
	"res://assets/characters/player/animations/swordsman_attack_a_04.png",
	"res://assets/characters/player/animations/swordsman_attack_a_05.png",
	"res://assets/characters/player/animations/swordsman_attack_a_06.png",
]
const ATTACK_B := [
	"res://assets/characters/player/animations/swordsman_attack_b_01.png",
	"res://assets/characters/player/animations/swordsman_attack_b_02.png",
	"res://assets/characters/player/animations/swordsman_attack_b_03.png",
	"res://assets/characters/player/animations/swordsman_attack_b_04.png",
	"res://assets/characters/player/animations/swordsman_attack_b_05.png",
	"res://assets/characters/player/animations/swordsman_attack_b_06.png",
]

var _failures: Array[String] = []
var _player: Node
var _hero: Sprite2D


func _ready() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await _physics_frames(35)

	_player = get_tree().get_first_node_in_group(&"player")
	_hero = _player.get_node_or_null("Visual/HeroSprite") as Sprite2D if _player else null
	_check(_hero != null, "player art sprite exists")
	if _hero == null:
		_finish()
		return

	await _record_attack(ATTACK_A, "attack A")
	await _record_attack(ATTACK_B, "attack B")
	_finish()


func _record_attack(expected: Array, label: String) -> void:
	Input.action_press(&"attack")
	await get_tree().physics_frame
	Input.action_release(&"attack")
	await get_tree().process_frame
	_check(int(_player.get("state")) == 5, "%s enters gameplay attack state" % label)

	var observed: Dictionary[String, bool] = {}
	var active_slash_aligned := false
	var recovery_trail_aligned := false
	var entered := false
	for i in 90:
		await get_tree().physics_frame
		await get_tree().process_frame
		if int(_player.get("state")) == 5:
			entered = true
			var path := _hero.texture.resource_path
			observed[path] = true
			var phase := int(_player.get("_attack_phase"))
			active_slash_aligned = active_slash_aligned or (path == expected[4] and phase == 1)
			recovery_trail_aligned = recovery_trail_aligned or (path == expected[5] and phase == 2)
		elif entered:
			break

	_check(not observed.is_empty(), "%s displays supplied frames" % label)
	for path in observed:
		_check(path in expected, "%s never flashes another character or action: %s" % [label, path.get_file()])
	_check(active_slash_aligned, "%s full slash matches the hitbox active phase" % label)
	_check(recovery_trail_aligned, "%s fading trail matches recovery" % label)
	_check(_hero.position == Vector2(0, -13), "%s keeps the grounded anchor" % label)
	_check(_hero.scale == Vector2(0.6, 0.6), "%s keeps the player display size" % label)


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
	Input.action_release(&"attack")
	if _failures.is_empty():
		print("\nAttack visual test passed")
	else:
		print("\nAttack visual test failed: %s" % ", ".join(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)
