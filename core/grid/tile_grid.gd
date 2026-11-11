class_name TileGrid
extends RefCounted
## 地圖格線：地形、特殊區域、建築占格與尋路。純資料，不含畫面。
## 地圖文字圖例：
##   #  不可通行地形（森林／岩石）       .  一般空地
##   P  星界傳送門保護區 escape_portal_zone
##   g  保護區入口（可通行、可建城牆，不屬於保護區）
##   T  巨魔出生區（不可建造）           1/2/3 精靈出生點（不可建造）
##   D  精靈基地入口的樹樁門（可通行地形；門關上時由門實體占格，不可建造）

var width := 0
var height := 0
var terrain := PackedByteArray()      # 1 = 不可通行
var portal_zone := PackedByteArray()  # 1 = 保護區
var gate := PackedByteArray()         # 1 = 保護區入口
var no_build := PackedByteArray()     # 1 = 出生區，不可建造
var troll_spawn_cells: Array[Vector2i] = []
var elf_spawns := {}                  # int(1..n) -> Vector2i
var stump_gate_cells: Array[Vector2i] = []
var occupancy := {}                   # Vector2i -> instance_id


func load_from_text(text: String) -> String:
	var lines: Array[String] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.length() > 0:
			lines.append(line)
	if lines.is_empty():
		return "地圖是空的"
	height = lines.size()
	width = lines[0].length()
	terrain.resize(width * height)
	portal_zone.resize(width * height)
	gate.resize(width * height)
	no_build.resize(width * height)
	terrain.fill(0)
	portal_zone.fill(0)
	gate.fill(0)
	no_build.fill(0)
	for y in height:
		if lines[y].length() != width:
			return "地圖第 %d 行長度 %d，應為 %d" % [y, lines[y].length(), width]
		for x in width:
			var ch := lines[y][x]
			var i := y * width + x
			match ch:
				"#":
					terrain[i] = 1
				".":
					pass
				"P":
					portal_zone[i] = 1
				"g":
					gate[i] = 1
				"D":
					no_build[i] = 1
					stump_gate_cells.append(Vector2i(x, y))
				"T":
					no_build[i] = 1
					troll_spawn_cells.append(Vector2i(x, y))
				"1", "2", "3", "4", "5", "6":
					no_build[i] = 1
					elf_spawns[int(ch)] = Vector2i(x, y)
				_:
					return "地圖含未知符號 '%s'（%d,%d）" % [ch, x, y]
	if troll_spawn_cells.is_empty():
		return "地圖缺少巨魔出生區 T"
	return ""


func idx(c: Vector2i) -> int:
	return c.y * width + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func is_terrain_blocked(c: Vector2i) -> bool:
	return not in_bounds(c) or terrain[idx(c)] == 1


func is_portal_zone(c: Vector2i) -> bool:
	return in_bounds(c) and portal_zone[idx(c)] == 1


func is_gate(c: Vector2i) -> bool:
	return in_bounds(c) and gate[idx(c)] == 1


func occupant(c: Vector2i) -> int:
	return occupancy.get(c, -1)


## 單位可走：在圖內、非地形阻擋、沒有任何建築（含傳送門）。
func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and terrain[idx(c)] == 0 and not occupancy.has(c)


func is_buildable_cell(c: Vector2i) -> bool:
	return in_bounds(c) and terrain[idx(c)] == 0 and no_build[idx(c)] == 0 and not occupancy.has(c)


func occupy(origin: Vector2i, size: Vector2i, instance_id: int) -> void:
	for c in GridMath.rect_cells(origin, size):
		occupancy[c] = instance_id


func vacate(origin: Vector2i, size: Vector2i) -> void:
	for c in GridMath.rect_cells(origin, size):
		occupancy.erase(c)


## 把相鄰的 D 格分組，每組是一扇門。回傳 [{origin, size}]。
func stump_gate_groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for c in stump_gate_cells:
		if seen.has(c):
			continue
		var group: Array[Vector2i] = [c]
		seen[c] = true
		var head := 0
		while head < group.size():
			var cur := group[head]
			head += 1
			for d in GridMath.DIRS4:
				var n := cur + d
				if not seen.has(n) and stump_gate_cells.has(n):
					seen[n] = true
					group.append(n)
		var lo := group[0]
		var hi := group[0]
		for g in group:
			lo = Vector2i(mini(lo.x, g.x), mini(lo.y, g.y))
			hi = Vector2i(maxi(hi.x, g.x), maxi(hi.y, g.y))
		out.append({"origin": lo, "size": hi - lo + Vector2i.ONE})
	return out


func portal_zone_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in height:
		for x in width:
			if portal_zone[y * width + x] == 1:
				out.append(Vector2i(x, y))
	return out


## 4 向洪水填充。extra_blocked：視為阻擋的額外格（例如預定放置的占格）。
func flood(starts: Array, extra_blocked: Dictionary = {}) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(width * height)
	seen.fill(0)
	var queue: Array[Vector2i] = []
	for s in starts:
		var c: Vector2i = s
		if in_bounds(c) and not seen[idx(c)]:
			seen[idx(c)] = 1
			queue.append(c)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for d in GridMath.DIRS4:
			var n := cur + d
			if not in_bounds(n) or seen[idx(n)]:
				continue
			if not is_walkable(n) or extra_blocked.has(n):
				continue
			seen[idx(n)] = 1
			queue.append(n)
	return seen


## BFS 找最短路徑到第一個滿足 goal 的格。回傳 {found, path}；path 不含起點。
func bfs_path(start: Vector2i, goal: Callable, extra_blocked: Dictionary = {}) -> Dictionary:
	if goal.call(start):
		return {"found": true, "path": []}
	var parent := {}
	parent[start] = start
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for d in GridMath.DIRS4:
			var n := cur + d
			if parent.has(n) or not is_walkable(n) or extra_blocked.has(n):
				continue
			parent[n] = cur
			if goal.call(n):
				var path: Array[Vector2i] = []
				var p := n
				while p != start:
					path.push_front(p)
					p = parent[p]
				return {"found": true, "path": path}
			queue.append(n)
	return {"found": false, "path": []}
