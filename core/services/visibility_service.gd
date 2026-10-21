class_name VisibilityService
extends RefCounted
## 建築與單位視野、瞭望塔、戰爭迷霧。每 tick 重算兩隊的可見格。
## 首版沒有隱身：只要所在格在視野內就算可見。

var sim: MatchSim
var visible := {"elves": PackedByteArray(), "trolls": PackedByteArray()}


func _init(s: MatchSim) -> void:
	sim = s


func recompute() -> void:
	var g: TileGrid = sim.grid
	for team in ["elves", "trolls"]:
		var arr := PackedByteArray()
		arr.resize(g.width * g.height)
		arr.fill(0)
		visible[team] = arr
	for u in sim.units.values():
		var unit: UnitState = u
		if unit.alive and unit.spawned:
			_reveal(unit.team, unit.pos, unit.vision)
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if not inst.is_alive():
			continue
		var r := float(sim.cfg.get("building_default_vision", 4))
		if inst.level >= 1:
			r = float(sim.defs.get_def(inst.def_id).level(inst.level).get("vision", r))
		_reveal(inst.team_id, inst.center(), r)


func _reveal(team: String, center: Vector2, r: float) -> void:
	var g: TileGrid = sim.grid
	var arr: PackedByteArray = visible[team]
	var x0 := maxi(0, int(floor(center.x - r)))
	var x1 := mini(g.width - 1, int(ceil(center.x + r)))
	var y0 := maxi(0, int(floor(center.y - r)))
	var y1 := mini(g.height - 1, int(ceil(center.y + r)))
	var r2 := r * r
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := x + 0.5 - center.x
			var dy := y + 0.5 - center.y
			if dx * dx + dy * dy <= r2:
				arr[y * g.width + x] = 1
	visible[team] = arr  # Packed 陣列是值型別，要寫回


func is_visible_to(team: String, pos: Vector2) -> bool:
	var g: TileGrid = sim.grid
	var c := GridMath.pos_to_cell(pos)
	if not g.in_bounds(c):
		return false
	var arr: PackedByteArray = visible[team]
	return arr.size() > 0 and arr[g.idx(c)] == 1


func is_cell_visible_to(team: String, c: Vector2i) -> bool:
	var g: TileGrid = sim.grid
	if not g.in_bounds(c):
		return false
	var arr: PackedByteArray = visible[team]
	return arr.size() > 0 and arr[g.idx(c)] == 1
