extends Node2D
## 靜態地形：只在開局畫一次（草地、森林、巢穴、保護區、門前小路）。

const CELL := 32.0

var grid: TileGrid
var tex_tree: Texture2D
var tex_tree2: Texture2D


func setup(g: TileGrid) -> void:
	grid = g
	tex_tree = load("res://art/sprites/tree.svg")
	tex_tree2 = load("res://art/sprites/tree2.svg")
	queue_redraw()


static func hash2(x: int, y: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


func _draw() -> void:
	if grid == null:
		return
	var g := grid
	var grass := [Color("#5d9140"), Color("#629744"), Color("#588a3c"), Color("#5f9342")]
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			var h := hash2(x, y)
			var rect := Rect2(Vector2(c) * CELL, Vector2(CELL, CELL))
			var col: Color = grass[h % 4]
			if g.is_terrain_blocked(c):
				col = Color("#2c4a25") if h % 3 else Color("#294421")
			elif g.is_portal_zone(c):
				col = Color("#93aaa6") if (x + y) % 2 == 0 else Color("#8aa29e")
			elif g.is_gate(c) or g.stump_gate_cells.has(c):
				col = Color("#a08a5c") if h % 2 else Color("#99835a")
			elif g.troll_spawn_cells.has(c):
				col = Color("#54463a") if h % 2 else Color("#4d4034")
			draw_rect(rect, col)
			if g.is_terrain_blocked(c):
				continue
			var o := Vector2(c) * CELL
			if g.is_portal_zone(c):
				draw_rect(rect.grow(-1.5), Color(1, 1, 1, 0.07), false, 1.0)
				if h % 7 == 0:
					draw_circle(o + Vector2(16, 16), 2.0, Color("#6fe0ff", 0.55))
			elif g.troll_spawn_cells.has(c):
				if h % 3 == 0:
					draw_line(o + Vector2(8, 20), o + Vector2(20, 14), Color("#e8dfc4"), 2.5)
					draw_circle(o + Vector2(8, 20), 2.2, Color("#e8dfc4"))
					draw_circle(o + Vector2(20, 14), 2.2, Color("#e8dfc4"))
				elif h % 3 == 1:
					draw_circle(o + Vector2(22, 22), 4.0, Color("#6f6f69"))
			elif not g.is_gate(c) and not g.stump_gate_cells.has(c):
				if h % 5 == 0:
					var p := o + Vector2(6 + h % 17, 10 + (h / 7) % 15)
					draw_line(p, p + Vector2(-3, -6), Color("#467a30"), 1.5)
					draw_line(p, p + Vector2(2, -7), Color("#467a30"), 1.5)
					draw_line(p, p + Vector2(5, -4), Color("#467a30"), 1.5)
				elif h % 29 == 0:
					var q := o + Vector2(8 + h % 13, 8 + (h / 5) % 13)
					draw_circle(q, 2.4, Color("#f4e27a") if h % 2 else Color("#f2f2f2"))
					draw_circle(q, 1.0, Color("#d98c2b"))
	# 森林：由上往下畫，下排蓋住上排
	for y in g.height:
		for x in g.width:
			if not g.is_terrain_blocked(Vector2i(x, y)):
				continue
			var h := hash2(x * 3 + 1, y * 5 + 2)
			var s := 46.0 + float(h % 9)
			var pos := Vector2(x, y) * CELL + Vector2(16 - s * 0.5 + float(h % 7) - 3.0, 18 - s * 0.72 + float((h / 7) % 5))
			draw_texture_rect(tex_tree2 if h % 4 == 0 else tex_tree, Rect2(pos, Vector2(s, s)), false)
