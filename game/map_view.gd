extends Node2D
## 占位色塊地圖。只讀取 MatchSim 的狀態來畫，不修改任何遊戲資料。

const CELL := 32.0

const C_OPEN := Color("#cbd8a8")
const C_FOREST := Color("#2f4a2b")
const C_ZONE := Color("#a9d6e8")
const C_GATE := Color("#e8d9a9")
const C_TROLL_SPAWN := Color("#d8a8a8")
const C_FOG := Color(0, 0, 0, 0.45)
const C_GRID := Color(0, 0, 0, 0.06)

var main  # game/main.gd


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var sim: MatchSim = main.sim
	var g: TileGrid = sim.grid
	var team: String = main.view_team()
	var font := ThemeDB.fallback_font
	# 地形
	for y in g.height:
		for x in g.width:
			var c := Vector2i(x, y)
			var col := C_OPEN
			if g.is_terrain_blocked(c):
				col = C_FOREST
			elif g.is_portal_zone(c):
				col = C_ZONE
			elif g.is_gate(c):
				col = C_GATE
			elif g.no_build[g.idx(c)] == 1:
				col = C_TROLL_SPAWN if g.troll_spawn_cells.has(c) else C_OPEN.darkened(0.08)
			draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), col)
			draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), C_GRID, false, 1.0)
	# 建築
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if inst.def_id == "escape_portal" and team == "trolls" and not sim.escape.revealed \
				and not _any_visible(sim, team, inst):
			continue
		_draw_building(sim, inst, font)
	# 單位
	for u in sim.units.values():
		var unit: UnitState = u
		if not unit.on_map():
			continue
		if unit.team != team and not sim.visibility.is_visible_to(team, unit.pos):
			continue
		_draw_unit(sim, unit, font)
	# 迷霧
	for y in g.height:
		for x in g.width:
			if not sim.visibility.is_cell_visible_to(team, Vector2i(x, y)) and not g.is_terrain_blocked(Vector2i(x, y)):
				draw_rect(Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL)), C_FOG)
	# 放置預覽
	if main.build_def != "" and main.preview_origin.x > -50:
		var d: BuildingDefinition = sim.defs.get_def(main.build_def)
		var ok: bool = main.preview_result.get("ok", false)
		var col := Color(0.2, 0.9, 0.3, 0.55) if ok else Color(0.95, 0.2, 0.2, 0.55)
		draw_rect(Rect2(Vector2(main.preview_origin) * CELL, Vector2(d.footprint) * CELL), col)
		draw_rect(Rect2(Vector2(main.preview_origin) * CELL, Vector2(d.footprint) * CELL), col.lightened(0.4), false, 2.0)
	# 選取框
	var sel: BuildingInstance = sim.buildings.get(main.selected_bid)
	if sel:
		draw_rect(Rect2(Vector2(sel.origin) * CELL - Vector2(3, 3), Vector2(sel.size) * CELL + Vector2(6, 6)), Color.YELLOW, false, 3.0)


func _any_visible(sim: MatchSim, team: String, inst: BuildingInstance) -> bool:
	for c in GridMath.rect_cells(inst.origin, inst.size):
		if sim.visibility.is_cell_visible_to(team, c):
			return true
	return false


func _draw_gate(inst: BuildingInstance, font: Font) -> void:
	var r := Rect2(Vector2(inst.origin) * CELL + Vector2(1, 6), Vector2(inst.size) * CELL - Vector2(2, 12))
	var wood := Color("#8b5a2b")
	match inst.state:
		BuildingInstance.ST_GATE_CLOSED:
			draw_rect(r, wood)
			for i in range(1, inst.size.x * 2):
				var x := r.position.x + r.size.x * i / (inst.size.x * 2)
				draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), wood.darkened(0.4), 2.0)
			draw_string(font, r.position + Vector2(4, r.size.y * 0.5 + 5), "門 關", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		BuildingInstance.ST_GATE_OPEN:
			draw_rect(Rect2(r.position, Vector2(6, r.size.y)), wood)
			draw_rect(Rect2(Vector2(r.end.x - 6, r.position.y), Vector2(6, r.size.y)), wood)
		BuildingInstance.ST_GATE_BROKEN:
			for i in 5:
				draw_rect(Rect2(r.position + Vector2(6 + i * 11, 4 + (i % 2) * 8), Vector2(7, 5)), wood.darkened(0.2))
			draw_string(font, r.position + Vector2(4, r.size.y + 4), "破", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c0392b"))
	if inst.hp < inst.max_hp:
		_bar(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x, 4)), float(inst.hp) / maxf(1.0, inst.max_hp), Color("#3cc24a"))


func _draw_building(sim: MatchSim, inst: BuildingInstance, font: Font) -> void:
	var d: BuildingDefinition = sim.defs.get_def(inst.def_id)
	if d.is_gate():
		_draw_gate(inst, font)
		return
	var r := Rect2(Vector2(inst.origin) * CELL + Vector2(2, 2), Vector2(inst.size) * CELL - Vector2(4, 4))
	var col := d.color
	if inst.state == BuildingInstance.ST_CONSTRUCTING:
		col = col.lerp(Color.WHITE, 0.55)
	draw_rect(r, col)
	draw_rect(r, col.darkened(0.5), false, 2.0)
	# 擁有者顏色條
	draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), main.player_color(inst.owner_player_id))
	var label := ""
	if d.is_portal():
		label = "門 %d/%d" % [sim.escape.stage, d.stages.size()]
	else:
		label = "%s%s" % [main.short_name(inst.def_id), ("" if inst.level == 0 else str(inst.level))]
	var fs := 11 if inst.size.x == 1 else 14
	draw_string(font, r.position + Vector2(3, r.size.y * 0.5 + 5), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 4, fs, Color.BLACK)
	var seen: bool = main.view_team() == "elves" or _any_visible(sim, main.view_team(), inst)
	if inst.def_id == "elf_house" and seen and sim.house.is_inside(inst.owner_player_id):
		draw_string(font, r.position + Vector2(r.size.x - 22, 18), "Zz", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#1d3d8f"))
	if inst.def_id == "elf_house" and seen and sim.house.repair_active(inst.owner_player_id):
		draw_arc(inst.center() * CELL, r.size.x * 0.6, 0, TAU, 32, Color("#4fd0ff"), 2.0)
	if d.is_portal():
		# 傳送門只顯示施工進度，不顯示 HP
		if sim.escape.status == EscapeService.STATUS_BUILDING:
			var p := float(sim.escape.progress_milli) / maxf(1.0, sim.escape.required_milli)
			_bar(Rect2(r.position + Vector2(0, r.size.y - 6), Vector2(r.size.x, 6)), p, Color("#4fd0ff"))
		return
	# HP 條
	_bar(Rect2(r.position + Vector2(0, r.size.y - 5), Vector2(r.size.x, 5)), float(inst.hp) / maxf(1.0, inst.max_hp), Color("#3cc24a"))
	if inst.has_job():
		var p2 := float(inst.job_progress_ticks) / maxf(1.0, inst.job_required_ticks)
		_bar(Rect2(r.position + Vector2(0, 5), Vector2(r.size.x, 4)), p2, Color("#f0c020"))


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0, 1), r.size.y)), col)


func _draw_unit(sim: MatchSim, u: UnitState, font: Font) -> void:
	var p := u.pos * CELL
	var radius := 10.0
	var col := Color("#2e8b57")
	match u.kind:
		UnitState.KIND_SOUL:
			col = Color(1, 1, 1, 0.6)
		UnitState.KIND_TROLL:
			col = Color("#7a1f1f")
			radius = 14.0
		UnitState.KIND_MINION:
			col = Color("#c46a1f")
			radius = 11.0
	if u.kind == UnitState.KIND_ELF:
		col = main.player_color(u.player_id)
	draw_circle(p, radius, col)
	draw_arc(p, radius, 0, TAU, 24, Color.BLACK, 2.0)
	if u.player_id == main.view_pid:
		draw_arc(p, radius + 4, 0, TAU, 24, Color.YELLOW, 2.0)
	if u.strongest_slow(sim.tick) > 0:
		draw_arc(p, radius + 2, 0, TAU, 24, Color("#5ab8d9"), 3.0)
	if sim.tick < u.rooted_until:
		draw_arc(p, radius + 6, 0, TAU, 8, Color("#3f9d3f"), 3.0)
	if sim.tick < u.marked_until:
		draw_string(font, p + Vector2(radius - 2, -radius), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd400"))
	if sim.tick < u.rampage_until:
		draw_arc(p, radius + 3, 0, TAU, 24, Color("#ff5a1f"), 2.0)
	if sim.tick < u.stunned_until:
		draw_string(font, p + Vector2(-8, -radius - 10), "暈", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	if u.channel_kind == "recall":
		var total := float(sim.cfg["troll"]["skills"]["recall"]["channel_sec"]) * sim.tick_rate
		_bar(Rect2(p + Vector2(-radius, radius + 4), Vector2(radius * 2, 4)), 1.0 - float(u.channel_until - sim.tick) / total, Color("#b07cff"))
	if u.kind != UnitState.KIND_SOUL:
		_bar(Rect2(p + Vector2(-radius, -radius - 7), Vector2(radius * 2, 4)), float(u.hp) / maxf(1.0, u.max_hp), Color("#e04040"))
	var tag := ""
	match u.kind:
		UnitState.KIND_ELF: tag = str(u.player_id)
		UnitState.KIND_SOUL: tag = "魂"
		UnitState.KIND_TROLL: tag = "巨%d" % u.level
		UnitState.KIND_MINION: tag = "僕%d" % u.level
	draw_string(font, p + Vector2(-6 if tag.length() < 2 else -11, 5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE if u.kind != UnitState.KIND_SOUL else Color.BLACK)
	# 走路路線
	if u.player_id == main.view_pid and not u.path.is_empty():
		var prev := p
		for c in u.path:
			var nx := GridMath.cell_center(c) * CELL
			draw_line(prev, nx, Color(1, 1, 0, 0.5), 2.0)
			prev = nx
