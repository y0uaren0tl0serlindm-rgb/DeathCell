class_name Room
extends Node2D
## 一个房间的场景侧：把 LevelGrid 生成的网格变成碰撞体、画面和摆放好的角色。
## 地形怎么生成、可不可通行，全在 LevelGrid 里（那边可以脱离场景树测试）。
##
## 注意：房间在 .tscn 里被设成 z_index = -1。
## _draw() 会铺满整块房间背景，如果和玩家同层，就会因为节点树顺序不同而把玩家盖住
## （换房间时新房间是后加进 world 的）。z_index 让绘制顺序不再依赖加入顺序。

# 显式 preload 跨文件的全局类：不这样写就依赖 .godot/ 里的全局类缓存，
# 干净检出或缓存过期时会解析失败、游戏起不来（issue #8）。
const Enemy = preload("res://src/enemies/enemy.gd")
const LevelGrid = preload("res://src/level/level_grid.gd")

const GruntScene := preload("res://src/enemies/grunt.tscn")
const BruteScene := preload("res://src/enemies/brute.tscn")
const DoorScene := preload("res://src/level/door.tscn")

@onready var terrain: StaticBody2D = $Terrain
@onready var entities: Node2D = $Entities

var grid: LevelGrid
## 这个房间实际是用哪个深度生成的（测试用来核对深度与生成参数一致）
var generated_depth := -1
var entrance_position: Vector2
var exit_position: Vector2

var _rng: RandomNumberGenerator
var _bg_color := Color(0.09, 0.08, 0.13)
var _tile_color := Color(0.22, 0.2, 0.3)
var _tile_top_color := Color(0.34, 0.32, 0.46)


func generate(rng: RandomNumberGenerator, depth: int) -> void:
	_rng = rng
	generated_depth = depth
	# 越深色调越冷，简单地做出"生物群系"的差异感
	var hue := fposmod(0.62 + depth * 0.07, 1.0)
	_bg_color = Color.from_hsv(hue, 0.35, 0.13)
	_tile_color = Color.from_hsv(hue, 0.3, 0.3)
	_tile_top_color = Color.from_hsv(hue, 0.25, 0.46)

	grid = LevelGrid.new()
	grid.build(rng, depth)
	if grid.repairs > 0:
		push_warning("房间生成后做了 %d 次可达性修复（depth=%d）" % [grid.repairs, depth])

	_build_collision()
	_place_actors(depth)
	queue_redraw()


func _build_collision() -> void:
	for child in terrain.get_children():
		child.queue_free()
	# 每行把连续的实心格合并成一个矩形，碰撞体数量能少一个数量级
	for y in LevelGrid.H:
		var x := 0
		while x < grid.width:
			if grid.solid[x][y] == 0:
				x += 1
				continue
			var start := x
			while x < grid.width and grid.solid[x][y] == 1:
				x += 1
			var run := x - start
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(run * LevelGrid.TILE, LevelGrid.TILE)
			shape.shape = rect
			shape.position = Vector2(
				(start + run * 0.5) * LevelGrid.TILE,
				(y + 0.5) * LevelGrid.TILE
			)
			terrain.add_child(shape)


func _place_actors(depth: int) -> void:
	for child in entities.get_children():
		child.queue_free()

	# 用落脚点而不是"每列的地面高度"—— 洞穴生成器里后者根本不存在
	entrance_position = grid.tile_to_world(grid.entrance_cell.x, grid.entrance_cell.y + 1) \
		+ Vector2(0, -2)
	exit_position = grid.tile_to_world(grid.exit_cell.x, grid.exit_cell.y + 1)

	var door := DoorScene.instantiate() as Node2D
	entities.add_child(door)
	door.position = exit_position

	var enemy_count := clampi(4 + depth, 4, 11)
	for spawn in _enemy_spawns(enemy_count, depth):
		var scene: PackedScene = BruteScene if spawn.elite else GruntScene
		var enemy := scene.instantiate() as Enemy
		entities.add_child(enemy)
		var cell: Vector2i = spawn.cell
		enemy.position = grid.tile_to_world(cell.x, cell.y + 1)


## 这个房间该在哪些格子上刷怪，以及刷小兵还是精英。
##
## 模板块里作者用 `n` / `N` 亲手标过刷怪点，那就照他标的来 —— 手绘关卡的价值
## 一半在地形，一半在"这一波怪摆在哪"。标的数量不够时用程序化的落脚点补齐。
## 另外两个生成器没有作者，全部走 spawn_footholds()：只挑"从入口真的走得到"
## 的落脚点，顺带敌人也能刷在平台/露台上。
func _enemy_spawns(count: int, depth: int) -> Array:
	var out: Array = []
	var taken := {}
	var authored: Array = grid.authored_spawns.duplicate()
	authored.shuffle()
	for spawn in authored:
		if out.size() >= count:
			break
		var cell: Vector2i = spawn.cell
		if not grid.is_standable(cell.x, cell.y):
			continue
		taken[cell] = true
		out.append(spawn)

	# 深度越大越容易刷精英（只作用于程序化补上来的那些，作者标的不改）
	var elite_chance := minf(0.12 + depth * 0.06, 0.45)
	for cell in grid.spawn_footholds(_rng, count - out.size()):
		if taken.has(cell):
			continue
		out.append({"cell": cell, "elite": _rng.randf() < elite_chance})
	return out


func world_size() -> Vector2:
	return grid.world_size() if grid else Vector2.ZERO


# ---------------------------------------------------------------- 渲染

func _draw() -> void:
	if grid == null:
		return
	draw_rect(Rect2(Vector2.ZERO, grid.world_size()), _bg_color)
	for x in grid.width:
		for y in LevelGrid.H:
			if grid.solid[x][y] == 0:
				continue
			var pos := Vector2(x * LevelGrid.TILE, y * LevelGrid.TILE)
			draw_rect(Rect2(pos, Vector2(LevelGrid.TILE, LevelGrid.TILE)), _tile_color)
			# 顶面高光：让地形轮廓一眼可读
			if y == 0 or grid.solid[x][y - 1] == 0:
				draw_rect(Rect2(pos, Vector2(LevelGrid.TILE, 3)), _tile_top_color)
