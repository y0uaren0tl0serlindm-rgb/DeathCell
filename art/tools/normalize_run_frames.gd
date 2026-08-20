extends SceneTree
## One-shot art pipeline helper. It removes generated matte pixels and places
## every run pose on the same canvas, scale, center, and foot baseline.

const FRAME_PATHS := [
	"res://assets/characters/player/animations/deathcell_hero_run_arcade_v4_01.png",
	"res://assets/characters/player/animations/deathcell_hero_run_arcade_v4_02.png",
	"res://assets/characters/player/animations/deathcell_hero_run_arcade_v4_03.png",
	"res://assets/characters/player/animations/deathcell_hero_run_arcade_v4_04.png",
	"res://assets/characters/player/animations/deathcell_hero_run_arcade_v4_05.png",
	"res://assets/characters/player/animations/deathcell_hero_run_arcade_v4_06.png",
	"res://assets/characters/player/animations/deathcell_hero_run_arcade_v4_07.png",
	"res://assets/characters/player/animations/deathcell_hero_run_arcade_v4_08.png",
]

const CANVAS_SIZE := Vector2i(2048, 2048)
const TARGET_BODY_HEIGHT := 1200.0
const MAX_CONTENT_WIDTH := 1900.0
const BASELINE_Y := 1632
const ALPHA_CUTOFF := 0.72


func _initialize() -> void:
	for path in FRAME_PATHS:
		_normalize_frame(path)
	quit()


func _normalize_frame(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	var image := Image.load_from_file(absolute_path)
	if image == null or image.is_empty():
		push_error("Could not load %s" % path)
		return

	var had_alpha := image.get_format() in [Image.FORMAT_LA8, Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH]
	image.convert(Image.FORMAT_RGBA8)
	if had_alpha:
		_harden_existing_alpha(image)
	else:
		_remove_connected_light_matte(image)
	_remove_small_islands(image)

	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		push_error("No visible pixels in %s" % path)
		return

	var content := image.get_region(used)
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
	var save_error := output.save_png(absolute_path)
	if save_error != OK:
		push_error("Could not save %s: %s" % [path, save_error])
	else:
		print("normalized %s source=%s output=%s at=%s" % [path, used, scaled_size, destination])


func _harden_existing_alpha(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a < ALPHA_CUTOFF:
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				image.set_pixel(x, y, color)


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


func _remove_small_islands(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var queue := PackedInt32Array()
	queue.resize(width * height)

	for start_y in height:
		for start_x in width:
			var start_index := start_y * width + start_x
			if visited[start_index] != 0 or image.get_pixel(start_x, start_y).a <= 0.0:
				continue
			var head := 0
			var tail := 1
			queue[0] = start_index
			visited[start_index] = 1
			while head < tail:
				var packed_position := queue[head]
				head += 1
				var x: int = packed_position % width
				var y: int = packed_position / width
				for neighbor in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
					if neighbor.x < 0 or neighbor.x >= width or neighbor.y < 0 or neighbor.y >= height:
						continue
					var neighbor_index: int = neighbor.y * width + neighbor.x
					if visited[neighbor_index] != 0 or image.get_pixel(neighbor.x, neighbor.y).a <= 0.0:
						continue
					visited[neighbor_index] = 1
					queue[tail] = neighbor_index
					tail += 1
			if tail < 256:
				for component_index in tail:
					var packed_position := queue[component_index]
					image.set_pixel(packed_position % width, packed_position / width, Color.TRANSPARENT)


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
