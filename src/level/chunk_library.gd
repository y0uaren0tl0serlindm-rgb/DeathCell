class_name ChunkLibrary
extends RefCounted
## 读盘、缓存、按深度筛选手绘模板块。
##
## 为什么和 RoomChunk 分成两个文件：静态工厂要在函数体里 `RoomChunk.new()`，
## 如果那段代码写在 room_chunk.gd 自己里面，就等于让一个脚本引用自己的
## `class_name` —— 那个名字要查 `.godot/global_script_class_cache.cfg`，
## 干净检出时缓存还不存在（issue #8）。分开之后这里正常 preload，缓存无关。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const RoomChunk = preload("res://src/level/room_chunk.gd")

const CHUNK_DIR := "res://assets/levels/chunks"

## 整个块库只加载一次。生成器每个房间都要挑块，重复读盘没有意义。
static var _library: Array = []
static var _loaded := false


## 全部可用的模板块。画错的块不会进来，但会 push_warning 报出文件名和原因 ——
## 画错了要立刻知道，而不是在游戏里纳闷某块为什么从来没出现过。
static func all() -> Array:
	if _loaded:
		return _library
	_loaded = true
	_library = []
	var dir := DirAccess.open(CHUNK_DIR)
	if dir == null:
		push_warning("模板块目录打不开：%s" % CHUNK_DIR)
		return _library
	var names := dir.get_files()
	names.sort()   # 目录顺序不保证稳定，排序让同一个 seed 每次挑到同一批块
	for file_name in names:
		if not file_name.ends_with(".room"):
			continue
		var path := "%s/%s" % [CHUNK_DIR, file_name]
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_warning("模板块读不出内容：%s" % path)
			continue
		var chunk := parse(text, path)
		if chunk.errors.is_empty():
			_library.append(chunk)
		else:
			push_warning("模板块 %s 有 %d 处问题，本次不会用到它：%s"
				% [file_name, chunk.errors.size(), ", ".join(chunk.errors)])
	return _library


## 连画错的块也一起返回。校验工具要拿它们来报错，游戏不要。
static func all_including_broken() -> Array:
	var out: Array = []
	var dir := DirAccess.open(CHUNK_DIR)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".room"):
			continue
		var path := "%s/%s" % [CHUNK_DIR, file_name]
		out.append(parse(FileAccess.get_file_as_string(path), path))
	return out


## 丢掉缓存重新读盘。只有工具和测试用得上。
static func reload() -> Array:
	_loaded = false
	return all()


## 深度落在 [depth_min, depth_max] 里的块
static func for_depth(depth: int) -> Array:
	var out: Array = []
	for chunk in all():
		var c: RoomChunk = chunk
		if depth >= c.depth_min and depth <= c.depth_max:
			out.append(c)
	return out


static func parse(text: String, path: String = "") -> RoomChunk:
	var chunk := RoomChunk.new()
	chunk.load_from_text(text, path)
	return chunk
