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
	grid.build(rng)
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
		while x < LevelGrid.W:
			if grid.solid[x][y] == 0:
				x += 1
				continue
			var start := x
			while x < LevelGrid.W and grid.solid[x][y] == 1:
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

	entrance_position = grid.tile_to_world(grid.entrance_x, grid.ground_row[grid.entrance_x]) \
		+ Vector2(0, -2)
	exit_position = grid.tile_to_world(grid.exit_x, grid.ground_row[grid.exit_x])

	var door := DoorScene.instantiate() as Node2D
	entities.add_child(door)
	door.position = exit_position

	var enemy_count := clampi(4 + depth, 4, 11)
	var used_columns: Array[int] = []
	for i in enemy_count:
		var x := _rng.randi_range(12, LevelGrid.W - 12)
		var tries := 0
		while _too_close(used_columns, x) and tries < 12:
			x = _rng.randi_range(12, LevelGrid.W - 12)
			tries += 1
		used_columns.append(x)

		var scene: PackedScene = GruntScene
		# 深度越大越容易刷精英
		if _rng.randf() < minf(0.12 + depth * 0.06, 0.45):
			scene = BruteScene
		var enemy := scene.instantiate() as Enemy
		entities.add_child(enemy)
		enemy.position = grid.tile_to_world(x, grid.ground_row[x])


func _too_close(columns: Array[int], x: int) -> bool:
	for c in columns:
		if absi(c - x) < 6:
			return true
	return false


func world_size() -> Vector2:
	return grid.world_size() if grid else Vector2.ZERO


# ---------------------------------------------------------------- 渲染

func _draw() -> void:
	if grid == null:
		return
	draw_rect(Rect2(Vector2.ZERO, grid.world_size()), _bg_color)
	for x in LevelGrid.W:
		for y in LevelGrid.H:
			if grid.solid[x][y] == 0:
				continue
			var pos := Vector2(x * LevelGrid.TILE, y * LevelGrid.TILE)
			draw_rect(Rect2(pos, Vector2(LevelGrid.TILE, LevelGrid.TILE)), _tile_color)
			# 顶面高光：让地形轮廓一眼可读
			if y == 0 or grid.solid[x][y - 1] == 0:
				draw_rect(Rect2(pos, Vector2(LevelGrid.TILE, 3)), _tile_top_color)
