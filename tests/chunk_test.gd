extends Node
## 手绘模板块的校验器 —— 画完 `.room` 就跑这个。
##   godot --headless --path . res://tests/chunk_test.tscn
##
## 它回答的是画图时唯一真正难判断的问题：**这块地形玩家走得通吗**。
## 判据不是我猜的，是 JumpModel 从 player.gd 的物理常数模拟出来的跳跃包络 ——
## 和关卡生成、可达性校验用的是同一张表。改了跳跃参数，这里的结论自己会跟着变。
##
## 出错时会把你画的图重新打印一遍，并把问题格子标出来：
##   `?` 站得住但从入口够不着     `!` 标记点本身画错了（比如脚下不是实心）

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const JumpModel = preload("res://src/level/jump_model.gd")
const LevelGrid = preload("res://src/level/level_grid.gd")
const RoomChunk = preload("res://src/level/room_chunk.gd")
const ChunkLibrary = preload("res://src/level/chunk_library.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_print_jump_cheatsheet()

	if RoomChunk.CHUNK_ROWS != LevelGrid.H:
		_fail("RoomChunk.CHUNK_ROWS(%d) 和 LevelGrid.H(%d) 对不上 —— 模板块塞不进房间"
			% [RoomChunk.CHUNK_ROWS, LevelGrid.H])

	ChunkLibrary.reload()
	var chunks := ChunkLibrary.all_including_broken()
	print("\n模板块目录 %s：%d 块" % [ChunkLibrary.CHUNK_DIR, chunks.size()])
	if chunks.is_empty():
		_fail("一块模板都没有 —— 至少画一块，不然 CHUNKS 生成器永远在退回智能体挖掘")

	for c in chunks:
		_check_chunk(c as RoomChunk)

	_check_seams(chunks)
	_check_assembly(chunks)

	if _failures.is_empty():
		print("\n模板块全部通过校验")
		get_tree().quit(0)
	else:
		print("\n失败 %d 项：" % _failures.size())
		for f in _failures:
			print("  ", f)
		get_tree().quit(1)


## 画图之前先看这张表：一次跳跃能上几格、能横跨几格。
## 平台高度只要超过"稳妥上升"，画得再好看玩家也站不上去（issue #7 的两次代价）。
func _print_jump_cheatsheet() -> void:
	print("跳跃包络（由 player.gd 的物理常数模拟得出，不是手推的）")
	print("  一次跳跃最多上升    %d 格   ← 平台高度的绝对上限" % JumpModel.max_rise())
	print("  稳妥上升            %d 格   ← 摆平台就按这个，极限值要求近乎完美的操作"
		% JumpModel.comfortable_rise())
	print("  平地最远横跨        %d 格   ← 断桥缺口别超过这个" % JumpModel.max_run())
	print("  玩家站立占          %d 格   ← 落脚点自己和头顶那格都必须是空的"
		% LevelGrid.BODY_TILES)
	print("  ⚠ 平台正下方是跳不上去的：会顶到平台底面。真实路线是在**边上**起跳再落上去，")
	print("    所以台子边缘外面那一列必须站得住人。")


# ---------------------------------------------------------------- 单块

func _check_chunk(chunk: RoomChunk) -> void:
	var label := "%s（%s）" % [chunk.display_name, chunk.source_path.get_file()]
	if not chunk.errors.is_empty():
		for e in chunk.errors:
			_fail("%s：%s" % [label, e])
		return

	# 单块拼成一个房间来验 —— 用的就是生成器和游戏里跑的同一条代码路径
	var grid := LevelGrid.new()
	grid.build_from_chunks([chunk])
	var reach := grid.reachable_cells()
	var marks := {}
	var bad := 0

	# 出口必须走得到。这是模板块唯一的硬性要求：
	# 拼接是把若干块串起来，任何一块内部断了，整层就断了。
	if not grid.exit_reachable():
		_fail("%s：从入口 `%s` 走不到出口 `%s`" % [label, RoomChunk.ENTRY, RoomChunk.EXIT])
		marks[chunk.exit_cell] = "!"
		bad += 1

	# 刷怪点必须站得住、而且玩家够得着 —— 够不着的怪只会隔着地形放冷枪
	for cell in chunk.spawns + chunk.elite_spawns:
		var world := Vector2i(cell.x + LevelGrid.BORDER, cell.y)
		if not grid.is_standable(world.x, world.y):
			_fail("%s：刷怪点 (%d, %d) 站不住人" % [label, cell.x + 1, cell.y + 1])
			marks[cell] = "!"
			bad += 1
		elif not reach.has(world):
			_fail("%s：刷怪点 (%d, %d) 玩家够不着" % [label, cell.x + 1, cell.y + 1])
			marks[cell] = "?"
			bad += 1

	# 够不着的落脚点是"看得见站不上去"的平台（issue #7）。不算硬伤，
	# 但每一个都是画的时候以为能上、实际上不去的地方，值得报出来。
	var stranded := 0
	for x in chunk.width:
		for y in RoomChunk.CHUNK_ROWS:
			if not chunk.is_standable(x, y):
				continue
			if reach.has(Vector2i(x + LevelGrid.BORDER, y)):
				continue
			stranded += 1
			if not marks.has(Vector2i(x, y)):
				marks[Vector2i(x, y)] = "?"

	var note := "" if stranded == 0 else "  ⚠ %d 格落脚点够不着" % stranded
	if bad == 0 and stranded == 0:
		print("  PASS  %-28s 宽 %d，刷怪点 %d，深度 %s"
			% [label, chunk.width, chunk.spawns.size() + chunk.elite_spawns.size(),
				_depth_text(chunk)])
		return

	print("  %s  %s%s" % ["FAIL" if bad > 0 else "WARN", label, note])
	print(chunk.to_ascii(marks))
	print("        `?` = 站得住但够不着    `!` = 这个标记点本身画错了")
	if bad == 0:
		# 够不着的落脚点单独作为不通过项报出来，但不用 _fail 拉红整个套件 ——
		# 岩层内部的小凹槽属于这一类，是可以接受的
		print("        （只是提醒：不影响通关，但玩家会看见上不去的地方）")


func _depth_text(chunk: RoomChunk) -> String:
	if chunk.depth_min == 0 and chunk.depth_max >= 9999:
		return "全部"
	if chunk.depth_max >= 9999:
		return "%d 起" % chunk.depth_min
	return "%d-%d" % [chunk.depth_min, chunk.depth_max]


# ---------------------------------------------------------------- 接缝

## 拼接器只在"上一块的出口 → 下一块的入口"这一步存在于跳跃包络时才接。
## 所以每一块都必须至少能接在某一块后面、也必须至少能接上某一块 ——
## 接不上的块画了也永远不会出现在游戏里，这种沉默的浪费要报出来。
func _check_seams(chunks: Array) -> void:
	if chunks.size() < 2:
		return
	print("\n接缝（从上一块的 `%s` 往右走一格到下一块的 `%s`）："
		% [RoomChunk.EXIT, RoomChunk.ENTRY])
	for a in chunks:
		var ca: RoomChunk = a
		if not ca.errors.is_empty():
			continue
		var followers: Array[String] = []
		for b in chunks:
			var cb: RoomChunk = b
			if cb.errors.is_empty() and JumpModel.can_reach(
					Vector2i(1, cb.entry.y - ca.exit_cell.y)):
				followers.append(cb.display_name)
		if followers.is_empty():
			_fail("%s 后面接不上任何一块（出口在第 %d 行，没有块的入口够得着）"
				% [ca.display_name, ca.exit_cell.y + 1])
		else:
			print("  %-12s → %s" % [ca.display_name, ", ".join(followers)])

	for b in chunks:
		var cb: RoomChunk = b
		if not cb.errors.is_empty():
			continue
		var reachable_from_any := false
		for a in chunks:
			var ca: RoomChunk = a
			if ca.errors.is_empty() and JumpModel.can_reach(
					Vector2i(1, cb.entry.y - ca.exit_cell.y)):
				reachable_from_any = true
				break
		if not reachable_from_any:
			_fail("没有任何一块能接在 %s 前面（入口在第 %d 行）"
				% [cb.display_name, cb.entry.y + 1])


# ---------------------------------------------------------------- 整层

## 真正走一遍生成器：多跑几个 seed × 深度，确认拼出来的整层是通的，
## 而且没有因为凑不出通路而悄悄退回智能体挖掘。
func _check_assembly(chunks: Array) -> void:
	if chunks.is_empty():
		return
	print("\n整层拼接：")
	var before := LevelGrid.generator
	LevelGrid.generator = LevelGrid.Generator.CHUNKS
	var total := 0
	var fell_back := 0
	var widths: Array[int] = []
	for depth in [0, 1, 3, 6, 12]:
		for s in 40:
			total += 1
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("chunk_%d_%d" % [s, depth])
			var grid := LevelGrid.new()
			grid.build(rng, depth)
			if grid.used_generator != LevelGrid.Generator.CHUNKS:
				fell_back += 1
				continue
			widths.append(grid.width)
			if not grid.exit_reachable():
				_fail("整层 seed=%d depth=%d 拼出来出口不可达" % [s, depth])
			if not grid.is_standable(grid.entrance_cell.x, grid.entrance_cell.y):
				_fail("整层 seed=%d depth=%d 入口站不住" % [s, depth])
	LevelGrid.generator = before

	var avg := 0
	for w in widths:
		avg += w
	print("  %d 个房间，平均宽 %d 列" % [total, avg / maxi(widths.size(), 1)])
	if fell_back > 0:
		_fail("%d/%d 个房间凑不出通路，退回了智能体挖掘 —— 手上的块接不成一条路"
			% [fell_back, total])


# ---------------------------------------------------------------- 工具

func _fail(label: String) -> void:
	print("  FAIL  ", label)
	_failures.append(label)
