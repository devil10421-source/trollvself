class_name GridMath
extends RefCounted
## 共用的格線幾何。所有距離都以「格」為單位，伺服器與手機用同一套算法。
## - 施工 / 修繕 / 傳送門範圍：單位所在格到建築占格矩形的 Chebyshev 距離（含斜向）。
## - 射程 / 視野 / 攻擊距離：單位連續座標到建築矩形（或塔中心）的歐氏距離。

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func rect_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			out.append(Vector2i(x, y))
	return out


static func cheb_cell_to_rect(cell: Vector2i, origin: Vector2i, size: Vector2i) -> int:
	var dx := 0
	if cell.x < origin.x:
		dx = origin.x - cell.x
	elif cell.x > origin.x + size.x - 1:
		dx = cell.x - (origin.x + size.x - 1)
	var dy := 0
	if cell.y < origin.y:
		dy = origin.y - cell.y
	elif cell.y > origin.y + size.y - 1:
		dy = cell.y - (origin.y + size.y - 1)
	return maxi(dx, dy)


static func point_to_rect(p: Vector2, origin: Vector2i, size: Vector2i) -> float:
	var cx := clampf(p.x, float(origin.x), float(origin.x + size.x))
	var cy := clampf(p.y, float(origin.y), float(origin.y + size.y))
	return p.distance_to(Vector2(cx, cy))


static func rect_center(origin: Vector2i, size: Vector2i) -> Vector2:
	return Vector2(origin) + Vector2(size) * 0.5


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)


static func pos_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.y)))
