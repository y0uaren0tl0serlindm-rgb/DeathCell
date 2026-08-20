extends SceneTree
## Removes the connected near-white GIF matte while preserving the original
## 498x498 canvas and per-frame offsets. Those offsets are part of the supplied
## animation and provide its vertical motion.

const FRAME_PATHS := [
	"res://assets/characters/player/animations/mario_run_01.png",
	"res://assets/characters/player/animations/mario_run_02.png",
	"res://assets/characters/player/animations/mario_run_03.png",
	"res://assets/characters/player/animations/mario_run_04.png",
	"res://assets/characters/player/animations/mario_run_05.png",
	"res://assets/characters/player/animations/mario_run_06.png",
	"res://assets/characters/player/animations/mario_run_07.png",
	"res://assets/characters/player/animations/mario_run_08.png",
]


func _initialize() -> void:
	for path in FRAME_PATHS:
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
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		push_error("Could not save %s: %s" % [path, save_error])
	else:
		print("prepared %s canvas=%s bounds=%s" % [path, image.get_size(), image.get_used_rect()])


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
