class_name Room
extends Node2D
## 程序化生成的一个房间。
## 用高度图 + 悬空平台构成地形，保证任何落差都在玩家的跳跃能力之内
## （跳跃高度约 3.4 格、跳跃距离约 6 格，见 player.gd 的常量）。
##
## 注意：房间在 .tscn 里被设成 z_index = -1。
## _draw() 会铺满整块房间背景，如果和玩家同层，就会因为节点树顺序不同而把玩家盖住
## （换房间时新房间是后加进 world 的）。z_index 让绘制顺序不再依赖加入顺序。

const TILE := 16
const GRID_W := 92
const GRID_H := 24

const MAX_STEP := 2          ## 相邻地面的最大高度差（格）
const MIN_GROUND_ROW := 13   ## 地面最高能到第几行
const MAX_GROUND_ROW := GRID_H - 3
const MAX_ROOF_ROW := 5      ## 洞顶最低能压到第几行
const MIN_LEDGE_RUN := 4     ## 一段平地至少多宽

const GruntScene := preload("res://src/enemies/grunt.tscn")
const BruteScene := preload("res://src/enemies/brute.tscn")
const DoorScene := preload("res://src/level/door.tscn")

@onready var terrain: StaticBody2D = $Terrain
@onready var entities: Node2D = $Entities

var solid: Array[PackedByteArray] = []
var ground_row: PackedInt32Array = PackedInt32Array()
var roof_row: PackedInt32Array = PackedInt32Array()
var entrance_position: Vector2
var exit_position: Vector2

var _rng: RandomNumberGenerator
var _bg_color := Color(0.09, 0.08, 0.13)
var _tile_color := Color(0.22, 0.2, 0.3)
var _tile_top_color := Color(0.34, 0.32, 0.46)


func generate(rng: RandomNumberGenerator, depth: int) -> void:
	_rng = rng
	# 越深色调越冷，简单地做出"生物群系"的差异感
	var hue := fposmod(0.62 + depth * 0.07, 1.0)
	_bg_color = Color.from_hsv(hue, 0.35, 0.13)
	_tile_color = Color.from_hsv(hue, 0.3, 0.3)
	_tile_top_color = Color.from_hsv(hue, 0.25, 0.46)

	_build_heightmap()
	_carve_platforms()
	_build_collision()
	_place_actors(depth)
	queue_redraw()


# ---------------------------------------------------------------- 地形

func _build_heightmap() -> void:
	solid.clear()
	for x in GRID_W:
		var col := PackedByteArray()
		col.resize(GRID_H)
		solid.append(col)

	ground_row = PackedInt32Array()
	ground_row.resize(GRID_W)
	roof_row = PackedInt32Array()
	roof_row.resize(GRID_W)

	var g := MAX_GROUND_ROW - 2
	var r := 2
	var since_step := 0
	for x in GRID_W:
		since_step += 1
		# 两次台阶之间至少隔 MIN_LEDGE_RUN 格，避免出现一格宽的锯齿地形
		if x > 6 and x < GRID_W - 8 and since_step >= MIN_LEDGE_RUN and _rng.randf() < 0.3:
			g = clampi(g + _rng.randi_range(-MAX_STEP, MAX_STEP), MIN_GROUND_ROW, MAX_GROUND_ROW)
			since_step = 0
		# 洞顶起伏：把大空盒变成一条有压迫感的通道
		if _rng.randf() < 0.2:
			r = clampi(r + _rng.randi_range(-1, 1), 1, MAX_ROOF_ROW)
		ground_row[x] = g
		roof_row[x] = mini(r, g - 6)   # 顶和地之间至少留 6 格通行高度
		for y in range(g, GRID_H):
			solid[x][y] = 1
		for y in range(0, roof_row[x] + 1):
			solid[x][y] = 1

	# 四周封边
	for y in GRID_H:
		solid[0][y] = 1
		solid[1][y] = 1
		solid[GRID_W - 1][y] = 1
		solid[GRID_W - 2][y] = 1

	# 出入口附近铲平，避免出生就卡在斜坡里
	for x in range(2, 7):
		_flatten_column(x, MAX_GROUND_ROW - 2)
	for x in range(GRID_W - 8, GRID_W - 2):
		_flatten_column(x, ground_row[GRID_W - 9])


func _flatten_column(x: int, row: int) -> void:
	row = clampi(row, MIN_GROUND_ROW, MAX_GROUND_ROW)
	ground_row[x] = row
	for y in range(GRID_H):
		solid[x][y] = 1 if (y >= row or y <= roof_row[x]) else 0


## 悬空平台：给战斗和走位加一层立体空间
func _carve_platforms() -> void:
	var count := _rng.randi_range(7, 12)
	for i in count:
		var x0 := _rng.randi_range(5, GRID_W - 12)
		var length := _rng.randi_range(3, 7)
		var y := clampi(ground_row[x0] - _rng.randi_range(3, 5), roof_row[x0] + 3, GRID_H - 4)
		for x in range(x0, mini(x0 + length, GRID_W - 2)):
			if y < ground_row[x] - 1:
				solid[x][y] = 1
				# 平台上方留出通行高度
				for dy in range(1, 4):
					if y - dy > roof_row[x]:
						solid[x][y - dy] = 0


func _build_collision() -> void:
	for child in terrain.get_children():
		child.queue_free()
	# 每行把连续的实心格合并成一个矩形，碰撞体数量能少一个数量级
	for y in GRID_H:
		var x := 0
		while x < GRID_W:
			if solid[x][y] == 0:
				x += 1
				continue
			var start := x
			while x < GRID_W and solid[x][y] == 1:
				x += 1
			var run := x - start
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(run * TILE, TILE)
			shape.shape = rect
			shape.position = Vector2((start + run * 0.5) * TILE, (y + 0.5) * TILE)
			terrain.add_child(shape)


# ---------------------------------------------------------------- 摆放

func _place_actors(depth: int) -> void:
	for child in entities.get_children():
		child.queue_free()

	entrance_position = _tile_to_world(4, ground_row[4]) + Vector2(0, -2)
	exit_position = _tile_to_world(GRID_W - 6, ground_row[GRID_W - 6])

	var door := DoorScene.instantiate() as Node2D
	entities.add_child(door)
	door.position = exit_position

	var enemy_count := clampi(4 + depth, 4, 11)
	var used_columns: Array[int] = []
	for i in enemy_count:
		var x := _rng.randi_range(12, GRID_W - 12)
		var tries := 0
		while _too_close(used_columns, x) and tries < 12:
			x = _rng.randi_range(12, GRID_W - 12)
			tries += 1
		used_columns.append(x)

		var scene: PackedScene = GruntScene
		# 深度越大越容易刷精英
		if _rng.randf() < minf(0.12 + depth * 0.06, 0.45):
			scene = BruteScene
		var enemy := scene.instantiate() as Enemy
		entities.add_child(enemy)
		enemy.position = _tile_to_world(x, ground_row[x])


func _too_close(columns: Array[int], x: int) -> bool:
	for c in columns:
		if absi(c - x) < 6:
			return true
	return false


func _tile_to_world(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * TILE, y * TILE)


func world_size() -> Vector2:
	return Vector2(GRID_W * TILE, GRID_H * TILE)


# ---------------------------------------------------------------- 渲染

func _draw() -> void:
	if solid.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, world_size()), _bg_color)
	for x in GRID_W:
		for y in GRID_H:
			if solid[x][y] == 0:
				continue
			var pos := Vector2(x * TILE, y * TILE)
			draw_rect(Rect2(pos, Vector2(TILE, TILE)), _tile_color)
			# 顶面高光：让地形轮廓一眼可读
			if y == 0 or solid[x][y - 1] == 0:
				draw_rect(Rect2(pos, Vector2(TILE, 3)), _tile_top_color)
