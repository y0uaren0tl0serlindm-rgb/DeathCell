extends SceneTree
## One-shot import preparation for the two generated v6 passing poses. The
## contact/down frames are exact v5 copies; only these opaque AI outputs need
## matte removal, scale matching, and baseline placement.

const GENERATED_PATHS := [
	"res://assets/characters/player/animations/deathcell_hero_run_v6_03_passing_a.png",
	"res://assets/characters/player/animations/deathcell_hero_run_v6_06_passing_b.png",
]
const CANVAS_SIZE := Vector2i(2048, 2048)
const TARGET_VISIBLE_HEIGHT := 1032
const BASELINE_Y := 1632


func _initialize() -> void:
	for path in GENERATED_PATHS:
		_prepare_frame(path)
	quit()


func _prepare_frame(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	var image := Image.load_from_file(absolute_path)
	if image == null or image.is_empty():
		push_error("Could not load %s" % path)
		return

	image.convert(Image.FORMAT_RGBA8)
	_remove_connected_light_matte(image)
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		push_error("No visible subject in %s" % path)
		return

	var subject := image.get_region(used)
	var scale_factor := float(TARGET_VISIBLE_HEIGHT) / float(subject.get_height())
	subject.resize(
		roundi(subject.get_width() * scale_factor),
		TARGET_VISIBLE_HEIGHT,
		Image.INTERPOLATE_NEAREST
	)

	var output := Image.create_empty(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	var destination := Vector2i(
		(CANVAS_SIZE.x - subject.get_width()) / 2,
		BASELINE_Y - subject.get_height()
	)
	output.blend_rect(subject, Rect2i(Vector2i.ZERO, subject.get_size()), destination)
	var save_error := output.save_png(absolute_path)
	if save_error != OK:
		push_error("Could not save %s: %s" % [path, save_error])
	else:
		print("prepared %s source_bounds=%s output_size=%s at=%s" % [
			path, used, subject.get_size(), destination
		])


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
		var x: int = packed_position % width
		var y: int = packed_position / width
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
	if darkest < 0.72 or brightest - darkest > 0.18:
		return tail
	queue[tail] = index
	return tail + 1
