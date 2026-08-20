extends SceneTree
## Art-pipeline helper: reports the non-transparent bounds of player frames.

const FRAME_PATHS := [
	"res://assets/characters/player/concepts/deathcell_hero_sprite_master_v2.png",
	"res://assets/characters/player/animations/deathcell_hero_run_v5_01_contact_a.png",
	"res://assets/characters/player/animations/deathcell_hero_run_v5_02_down_a.png",
	"res://assets/characters/player/animations/deathcell_hero_run_v5_03_passing_a.png",
	"res://assets/characters/player/animations/deathcell_hero_run_v5_04_high_a.png",
	"res://assets/characters/player/animations/deathcell_hero_run_v5_05_contact_b.png",
	"res://assets/characters/player/animations/deathcell_hero_run_v5_06_down_b.png",
	"res://assets/characters/player/animations/deathcell_hero_run_v5_07_passing_b.png",
	"res://assets/characters/player/animations/deathcell_hero_run_v5_08_high_b.png",
]


func _initialize() -> void:
	for path in FRAME_PATHS:
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		print("%s canvas=%sx%s bounds=%s" % [path, image.get_width(), image.get_height(), image.get_used_rect()])
	quit()
