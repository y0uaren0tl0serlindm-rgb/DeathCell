extends SceneTree
## One-shot art pipeline helper for the generated 4x2 run-cycle sheet.

const SOURCE_PATH := "res://assets/characters/player/animations/deathcell_hero_run_cycle_sheet_v2.png"
const OUTPUT_PATHS := [
	"res://assets/characters/player/animations/deathcell_hero_run_cycle_v2_01_contact_a.png",
	"res://assets/characters/player/animations/deathcell_hero_run_cycle_v2_02_down_a.png",
	"res://assets/characters/player/animations/deathcell_hero_run_cycle_v2_03_pass_a.png",
	"res://assets/characters/player/animations/deathcell_hero_run_cycle_v2_04_high_a.png",
	"res://assets/characters/player/animations/deathcell_hero_run_cycle_v2_05_contact_b.png",
	"res://assets/characters/player/animations/deathcell_hero_run_cycle_v2_06_down_b.png",
	"res://assets/characters/player/animations/deathcell_hero_run_cycle_v2_07_pass_b.png",
	"res://assets/characters/player/animations/deathcell_hero_run_cycle_v2_08_high_b.png",
]

const COLUMNS := 4
const ROWS := 2
const CANVAS_SIZE := Vector2i(1536, 1536)
const TARGET_BODY_HEIGHT := 1200.0
const MAX_CONTENT_WIDTH := 1420.0
const BASELINE_Y := 1380


func _initialize() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_PATH))
	if sheet == null or sheet.is_empty():
		push_error("Could not load %s" % SOURCE_PATH)
		quit(1)
		return

	for index in OUTPUT_PATHS.size():
		var column := index % COLUMNS
		var row := index / COLUMNS
		var x0 := roundi(float(column) * sheet.get_width() / COLUMNS)
		var x1 := roundi(float(column + 1) * sheet.get_width() / COLUMNS)
		var y0 := roundi(float(row) * sheet.get_height() / ROWS)
		var y1 := roundi(float(row + 1) * sheet.get_height() / ROWS)
		var frame := sheet.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
		frame.convert(Image.FORMAT_RGBA8)
		_remove_connected_light_matte(frame)
		_save_normalized(frame, OUTPUT_PATHS[index])

	quit()


func _save_normalized(frame: Image, output_path: String) -> void:
	var used := frame.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		push_error("No visible pixels for %s" % output_path)
		return

	var content := frame.get_region(used)
	var scale_factor: float = minf(
		TARGET_BODY_HEIGHT / float(content.get_height()),
		MAX_CONTENT_WIDTH / float(content.get_width())
	)
	var scaled_size := Vector2i(
		maxi(1, roundi(content.get_width() * scale_factor)),
		maxi(1, roundi(content.get_height() * scale_factor))
	)
	content.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_NEAREST)

	var output := Image.create_empty(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	var destination := Vector2i(
		(CANVAS_SIZE.x - scaled_size.x) / 2,
		BASELINE_Y - scaled_size.y
	)
	output.blend_rect(content, Rect2i(Vector2i.ZERO, scaled_size), destination)
	var absolute_output := ProjectSettings.globalize_path(output_path)
	var save_error := output.save_png(absolute_output)
	if save_error != OK:
		push_error("Could not save %s: %s" % [output_path, save_error])
	else:
		print("extracted %s source=%s output=%s" % [output_path, used, scaled_size])


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
