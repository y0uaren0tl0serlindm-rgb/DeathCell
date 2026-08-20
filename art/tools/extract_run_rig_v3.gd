extends SceneTree
## Extracts the deterministic two-leg run rig from generated modular art.

const TORSO_SOURCE := "res://assets/characters/player/animations/deathcell_hero_run_torso_source_v3.png"
const TORSO_OUTPUT := "res://assets/characters/player/animations/deathcell_hero_run_torso_v3.png"
const PARTS_SOURCE := "res://assets/characters/player/animations/deathcell_hero_run_leg_parts_sheet_v3.png"
const PART_OUTPUTS := [
	"res://assets/characters/player/animations/deathcell_hero_run_near_upper_v3.png",
	"res://assets/characters/player/animations/deathcell_hero_run_near_lower_v3.png",
	"res://assets/characters/player/animations/deathcell_hero_run_far_upper_v3.png",
	"res://assets/characters/player/animations/deathcell_hero_run_far_lower_v3.png",
]

const COLUMNS := 2
const ROWS := 2
const CELL_MARGIN := 8
const PART_PADDING := 8


func _initialize() -> void:
	_extract_torso()
	_extract_parts()
	quit()


func _extract_torso() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(TORSO_SOURCE))
	image.convert(Image.FORMAT_RGBA8)
	_remove_connected_light_matte(image)
	var error := image.save_png(ProjectSettings.globalize_path(TORSO_OUTPUT))
	if error != OK:
		push_error("Could not save run torso: %s" % error)
	else:
		print("saved %s canvas=%sx%s bounds=%s" % [TORSO_OUTPUT, image.get_width(), image.get_height(), image.get_used_rect()])


func _extract_parts() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(PARTS_SOURCE))
	for index in PART_OUTPUTS.size():
		var column := index % COLUMNS
		var row := index / COLUMNS
		var x0 := roundi(float(column) * sheet.get_width() / COLUMNS)
		var x1 := roundi(float(column + 1) * sheet.get_width() / COLUMNS)
		var y0 := roundi(float(row) * sheet.get_height() / ROWS)
		var y1 := roundi(float(row + 1) * sheet.get_height() / ROWS)
		var part := sheet.get_region(Rect2i(
			x0 + CELL_MARGIN,
			y0 + CELL_MARGIN,
			x1 - x0 - CELL_MARGIN * 2,
			y1 - y0 - CELL_MARGIN * 2
		))
		part.convert(Image.FORMAT_RGBA8)
		_remove_connected_light_matte(part)
		_save_joint_centered_part(part, PART_OUTPUTS[index])


func _save_joint_centered_part(part: Image, output_path: String) -> void:
	var used := part.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		push_error("No visible pixels for %s" % output_path)
		return

	var joint_sample_height := maxi(1, roundi(used.size.y * 0.14))
	var x_sum := 0.0
	var sample_count := 0
	for y in range(used.position.y, used.position.y + joint_sample_height):
		for x in range(used.position.x, used.end.x):
			if part.get_pixel(x, y).a > 0.5:
				x_sum += x
				sample_count += 1
	var joint_x := roundi(x_sum / sample_count) if sample_count > 0 else used.get_center().x
	var left_extent := joint_x - used.position.x
	var right_extent := used.end.x - joint_x
	var output_width := 2 * maxi(left_extent, right_extent) + PART_PADDING * 2
	var output_height := used.size.y + PART_PADDING * 2
	var output := Image.create_empty(output_width, output_height, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	var destination := Vector2i(output_width / 2 - (joint_x - used.position.x), PART_PADDING)
	output.blend_rect(part, used, destination)
	var error := output.save_png(ProjectSettings.globalize_path(output_path))
	if error != OK:
		push_error("Could not save %s: %s" % [output_path, error])
	else:
		print("saved %s size=%sx%s joint=(%s,%s)" % [output_path, output_width, output_height, output_width / 2, PART_PADDING])


func _remove_connected_light_matte(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var queue := PackedInt32Array()
	queue.resize(width * height)
	var head := 0
	var tail := 0

	for x in width:
		tail = _try_enqueue_background(image, visited, queue, tail, x, 0)
		tail = _try_enqueue_background(image, visited, queue, tail, x, height - 1)
	for y in height:
		tail = _try_enqueue_background(image, visited, queue, tail, 0, y)
		tail = _try_enqueue_background(image, visited, queue, tail, width - 1, y)

	while head < tail:
		var packed_position := queue[head]
		head += 1
		var x := packed_position % width
		var y := packed_position / width
		image.set_pixel(x, y, Color.TRANSPARENT)
		if x > 0:
			tail = _try_enqueue_background(image, visited, queue, tail, x - 1, y)
		if x + 1 < width:
			tail = _try_enqueue_background(image, visited, queue, tail, x + 1, y)
		if y > 0:
			tail = _try_enqueue_background(image, visited, queue, tail, x, y - 1)
		if y + 1 < height:
			tail = _try_enqueue_background(image, visited, queue, tail, x, y + 1)


func _try_enqueue_background(
	image: Image,
	visited: PackedByteArray,
	queue: PackedInt32Array,
	tail: int,
	x: int,
	y: int
) -> int:
	var index := y * image.get_width() + x
	if visited[index] != 0:
		return tail
	visited[index] = 1
	var color := image.get_pixel(x, y)
	var brightest := maxf(color.r, maxf(color.g, color.b))
	var darkest := minf(color.r, minf(color.g, color.b))
	if darkest < 0.88 or brightest - darkest > 0.08:
		return tail
	queue[tail] = index
	return tail + 1
