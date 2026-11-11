extends Node2D
## 地圖畫面：建築、單位、特效。只讀取 MatchSim 的狀態來畫，不修改任何遊戲資料。
## 美術是 art/sprites 的原創 SVG（tools/gen_art.py 產生）。地形在 terrain_layer、迷霧在 fog_layer。

const CELL := 32.0
const SPRITES := ["elf_body", "elf_head", "soul", "troll", "house", "grove", "hall", "wall_wood", "wall_stone",
	"arrow_tower", "frost_tower", "watch_tower", "repair_post", "gate_closed", "gate_open", "gate_broken", "portal"]
const DEF_SPRITE := {"elf_house": "house", "lumber_grove": "grove", "craft_hall": "hall", "arrow_tower": "arrow_tower",
	"frost_tower": "frost_tower", "watch_tower": "watch_tower", "repair_post": "repair_post", "escape_portal": "portal"}
const WALL_TINT := [Color.WHITE, Color("#cfcfc8"), Color("#9aa6ba"), Color("#c3b2ff")]

var main  # game/main.gd
var tex := {}
var terrain: Node2D
var fog: Node2D
var _last_pos := {}    # unit_id -> Vector2
var _facing := {}      # unit_id -> -1 / 1
var _moving := {}      # unit_id -> bool
var font: Font


func _ready() -> void:
	for n in SPRITES:
		tex[n] = load("res://art/sprites/%s.svg" % n)
	terrain = Node2D.new()
	terrain.set_script(load("res://game/terrain_layer.gd"))
	terrain.show_behind_parent = true
	add_child(terrain)
	fog = Node2D.new()
	fog.set_script(load("res://game/fog_layer.gd"))
	fog.main = main
	add_child(fog)
	font = ThemeDB.fallback_font


func on_new_match() -> void:
	terrain.setup(main.sim.grid)
	_last_pos.clear()
	_facing.clear()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var sim: MatchSim = main.sim
	var team: String = main.view_team()
	# 建築：由上往下畫
	var list: Array = sim.buildings.values()
	list.sort_custom(func(a, b): return a.origin.y < b.origin.y or (a.origin.y == b.origin.y and a.instance_id < b.instance_id))
	for b in list:
		var inst: BuildingInstance = b
		if inst.def_id == "escape_portal" and team == "trolls" and not sim.escape.revealed and not _any_visible(sim, team, inst):
			continue
		_draw_building(sim, inst, team)
	# 單位
	var units: Array = sim.units.values()
	units.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for u in units:
		var unit: UnitState = u
		if not unit.on_map():
			continue
		if unit.team != team and not sim.visibility.is_visible_to(team, unit.pos):
			continue
		_draw_unit(sim, unit)
	_draw_fx(sim)


func _any_visible(sim: MatchSim, team: String, inst: BuildingInstance) -> bool:
	for c in GridMath.rect_cells(inst.origin, inst.size):
		if sim.visibility.is_cell_visible_to(team, c):
			return true
	return false


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r.grow(1), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0, 1), r.size.y)), col)


static func hp_color(frac: float) -> Color:
	if frac > 0.6:
		return Color("#43d14f")
	if frac > 0.3:
		return Color("#e8c230")
	return Color("#e04a3a")


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ---------- 建築 ----------

func _draw_building(sim: MatchSim, inst: BuildingInstance, team: String) -> void:
	var d: BuildingDefinition = sim.defs.get_def(inst.def_id)
	var o := Vector2(inst.origin) * CELL
	var sz := Vector2(inst.size) * CELL
	var seen: bool = team == "elves" or _any_visible(sim, team, inst)
	if d.is_gate():
		var name := "gate_open"
		if inst.state == BuildingInstance.ST_GATE_CLOSED:
			name = "gate_closed"
		elif inst.state == BuildingInstance.ST_GATE_BROKEN:
			name = "gate_broken"
		draw_texture_rect(tex[name], Rect2(o + Vector2(-8, -10), Vector2(sz.x + 16, (sz.x + 16) * 0.5)), false)
		if inst.hp < inst.max_hp:
			_bar(Rect2(o + Vector2(6, -14), Vector2(sz.x - 12, 4)), float(inst.hp) / maxf(1.0, inst.max_hp), hp_color(float(inst.hp) / maxf(1.0, inst.max_hp)))
		_draw_repair_marks(sim, inst)
		return
	var mod := Color.WHITE
	var sprite: String = DEF_SPRITE.get(inst.def_id, "")
	if inst.def_id == "wall":
		sprite = "wall_wood" if inst.level <= 1 else "wall_stone"
		mod = WALL_TINT[clampi(inst.level, 1, 4) - 1]
	if inst.state == BuildingInstance.ST_CONSTRUCTING:
		mod.a = 0.55
	var rect := Rect2(o + Vector2(-5, -12), sz + Vector2(10, 14))
	if inst.size.x >= 2:
		rect = Rect2(o + Vector2(-6, -12), sz + Vector2(12, 14))
	if d.is_portal():
		rect = Rect2(o - Vector2(4, 4), sz + Vector2(8, 8))
		var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 300.0)
		mod = Color(pulse, pulse, 1.0, 0.6 + 0.4 * float(sim.escape.stage) / 3.0)
	draw_texture_rect(tex[sprite], rect, false, mod)
	if inst.def_id == "wall" and inst.level >= 4:
		draw_rect(Rect2(o, sz).grow(-2), Color("#b79bff", 0.35 + 0.2 * sin(Time.get_ticks_msec() / 250.0)), false, 2.0)
	# 擁有者顏色旗
	if not d.is_portal():
		var flag := o + Vector2(2, sz.y - 6)
		draw_circle(flag, 4.5, Color(0, 0, 0, 0.8))
		draw_circle(flag, 3.2, main.player_color(inst.owner_player_id))
	if d.is_portal():
		_text(o + Vector2(sz.x * 0.5 - 14, -8), "%d / %d" % [sim.escape.stage, d.stages.size()], 13, Color("#bff3ff"))
		if sim.escape.status == EscapeService.STATUS_BUILDING:
			_bar(Rect2(o + Vector2(8, sz.y + 2), Vector2(sz.x - 16, 5)), float(sim.escape.progress_milli) / maxf(1.0, sim.escape.required_milli), Color("#4fd0ff"))
		return
	# 等級點
	for i in inst.level:
		if d.max_level() > 1:
			var pp := o + Vector2(sz.x - 5 - i * 6, sz.y - 5)
			draw_circle(pp, 3.0, Color(0, 0, 0, 0.8))
			draw_circle(pp, 2.0, Color("#ffd24a"))
	var frac := float(inst.hp) / maxf(1.0, inst.max_hp)
	if inst.hp < inst.max_hp or inst.instance_id == main.selected_bid:
		_bar(Rect2(o + Vector2(3, -15), Vector2(sz.x - 6, 4)), frac, hp_color(frac))
	if inst.has_job():
		_bar(Rect2(o + Vector2(3, -9), Vector2(sz.x - 6, 3)), float(inst.job_progress_ticks) / maxf(1.0, inst.job_required_ticks), Color("#f0c020"))
	if inst.def_id == "elf_house" and seen:
		if sim.house.is_inside(inst.owner_player_id):
			var bob := sin(Time.get_ticks_msec() / 400.0) * 2.0
			_text(o + Vector2(sz.x - 14, -2 + bob), "Zz", 13, Color("#dff1ff"))
		if sim.house.repair_active(inst.owner_player_id):
			draw_arc(o + sz * 0.5, sz.x * 0.62, 0, TAU, 32, Color("#7dffb0", 0.8), 2.0)
	_draw_repair_marks(sim, inst)


## 正在被樹屋修復鈕修的建築：冒綠色加號。
func _draw_repair_marks(sim: MatchSim, inst: BuildingInstance) -> void:
	if not RepairService.is_wall_like(inst.def_id) or not sim.house.repair_active(inst.owner_player_id):
		return
	var target: BuildingInstance = sim.house.repair_target(inst.owner_player_id)
	if target != inst:
		return
	var t := fmod(Time.get_ticks_msec() / 600.0, 1.0)
	var c := inst.center() * CELL + Vector2(0, -8 - t * 14)
	var col := Color("#7dffb0", 1.0 - t)
	draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), col, 3.0)
	draw_line(c + Vector2(0, -5), c + Vector2(0, 5), col, 3.0)


# ---------- 單位 ----------

func _draw_unit(sim: MatchSim, u: UnitState) -> void:
	var p := u.pos * CELL
	var last: Vector2 = _last_pos.get(u.id, u.pos)
	var dx := u.pos.x - last.x
	if absf(dx) > 0.001:
		_facing[u.id] = 1 if dx > 0 else -1
	_moving[u.id] = u.pos.distance_to(last) > 0.0005
	_last_pos[u.id] = u.pos
	var face: int = _facing.get(u.id, 1)
	var bob := absf(sin(Time.get_ticks_msec() / 90.0 + u.id)) * 2.5 if _moving.get(u.id, false) else 0.0
	var mine: bool = u.player_id == main.view_pid
	var size := 36.0
	match u.kind:
		UnitState.KIND_TROLL: size = 58.0 + u.level * 1.6
		UnitState.KIND_MINION: size = 44.0 + u.level * 0.8
		UnitState.KIND_SOUL: size = 34.0
	# 腳下的圈：自己 = 綠色選取圈；其他 = 隊伍色
	var ring_col: Color = Color("#49ff62") if mine else (main.player_color(u.player_id) if u.team == "elves" else Color("#ff5a4a"))
	var ring_r := size * 0.36
	draw_set_transform(p + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, ring_r, 0, TAU, 28, Color(0, 0, 0, 0.5), 4.0 if mine else 3.0)
	draw_arc(Vector2.ZERO, ring_r, 0, TAU, 28, ring_col, 2.2 if mine else 1.4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var top := p + Vector2(-size * 0.5, -size * 0.80 - bob)
	var rect := Rect2(top, Vector2(size, size))
	if face < 0:
		rect = Rect2(top + Vector2(size, 0), Vector2(-size, size))
	match u.kind:
		UnitState.KIND_ELF:
			draw_texture_rect(tex["elf_body"], rect, false, main.player_color(u.player_id).lightened(0.25))
			draw_texture_rect(tex["elf_head"], rect, false)
		UnitState.KIND_SOUL:
			var float_y := sin(Time.get_ticks_msec() / 350.0 + u.id) * 3.0
			rect.position.y += float_y - 4
			draw_texture_rect(tex["soul"], rect, false, Color(1, 1, 1, 0.9))
		UnitState.KIND_TROLL:
			var m := Color.WHITE
			if sim.tick < u.rampage_until:
				m = Color(1.0, 0.62, 0.55)
			draw_texture_rect(tex["troll"], rect, false, m)
		UnitState.KIND_MINION:
			draw_texture_rect(tex["troll"], rect, false, Color(1.0, 0.82, 0.62))
	# 狀態
	if u.strongest_slow(sim.tick) > 0:
		draw_arc(p + Vector2(0, -size * 0.3), size * 0.42, 0, TAU, 20, Color("#8fe3ff", 0.9), 2.5)
	if sim.tick < u.rooted_until:
		for i in 6:
			var a := TAU * i / 6.0 + Time.get_ticks_msec() / 500.0
			draw_circle(p + Vector2(cos(a) * size * 0.4, sin(a) * size * 0.2 + 2), 3.5, Color("#3fa53f"))
	if sim.tick < u.marked_until:
		_text(p + Vector2(-7, -size * 0.92), "★", 16, Color("#ffd400"))
	if sim.tick < u.stunned_until:
		_text(p + Vector2(-8, -size * 0.92), "暈", 13, Color.WHITE)
	if u.smash_ready:
		draw_arc(p + Vector2(size * 0.32, -size * 0.6), 7.0, 0, TAU, 12, Color("#ffb347"), 2.5)
	# 血條與標籤
	var bar_w := size * 0.8
	var by := p.y - size * 0.86 - bob
	if u.kind != UnitState.KIND_SOUL:
		var frac := float(u.hp) / maxf(1.0, u.max_hp)
		_bar(Rect2(Vector2(p.x - bar_w * 0.5, by - 6), Vector2(bar_w, 4)), frac, hp_color(frac))
	if u.team == "trolls":
		_text(Vector2(p.x - bar_w * 0.5, by - 9), "Lv%d" % u.level, 11, Color("#ffd24a"))
	if u.channel_kind == "recall":
		var total := float(sim.cfg["troll"]["skills"]["recall"]["channel_sec"]) * sim.tick_rate
		_bar(Rect2(Vector2(p.x - bar_w * 0.5, p.y + 8), Vector2(bar_w, 4)), 1.0 - float(u.channel_until - sim.tick) / total, Color("#b07cff"))
	if mine and not u.path.is_empty():
		var prev := p
		for c in u.path:
			var nx := GridMath.cell_center(c) * CELL
			draw_line(prev, nx, Color(1, 1, 1, 0.28), 2.0)
			prev = nx
		draw_circle(prev, 4.0, Color("#49ff62", 0.8))


# ---------- 特效 ----------

func _draw_fx(sim: MatchSim) -> void:
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for f in main.fx:
		var t := float(now - int(f["t0"])) / float(f["ttl"])
		if t >= 1.0:
			continue
		keep.append(f)
		var a: Vector2 = f["a"] * CELL
		var team: String = main.view_team()
		if not sim.visibility.is_visible_to(team, f["a"]) and f["kind"] != "roar":
			continue
		match str(f["kind"]):
			"arrow":
				var b: Vector2 = f["b"] * CELL + Vector2(0, -14)
				var from := a + Vector2(0, -18)
				var head := from.lerp(b, t)
				var dir := (b - from).normalized()
				draw_line(head - dir * 10.0, head, Color("#f2e6c8"), 2.0)
				draw_line(head - dir * 3.0, head, Color("#6b4420"), 3.0)
			"frost":
				var b2: Vector2 = f["b"] * CELL + Vector2(0, -14)
				var orb := (a + Vector2(0, -20)).lerp(b2, t)
				draw_circle(orb, 5.0, Color("#bfeaff", 0.9))
				draw_circle(orb, 2.5, Color.WHITE)
			"hit":
				for i in 4:
					var ang := TAU * i / 4.0 + 0.6
					var d := Vector2(cos(ang), sin(ang))
					draw_line(a + d * (4 + t * 6), a + d * (9 + t * 12), Color("#ffe27a", 1.0 - t), 2.5 * float(f.get("scale", 1.0)))
			"roar":
				draw_arc(a, float(f["r"]) * CELL * t, 0, TAU, 48, Color("#ff8a3a", 0.9 * (1.0 - t)), 4.0)
				draw_arc(a, float(f["r"]) * CELL * t * 0.7, 0, TAU, 48, Color("#ffd27a", 0.6 * (1.0 - t)), 2.0)
			"ring":
				draw_arc(a + Vector2(0, -10), 10.0 + 26.0 * t, 0, TAU, 32, Color(f["col"], 1.0 - t), 3.0)
			"text":
				_text(a + Vector2(-16, -30 - t * 26), str(f["s"]), 15, Color(f["col"], 1.0 - t * t))
			"skull":
				_text(a + Vector2(-8, -6 - t * 10), "✝", 20, Color(1, 1, 1, 1.0 - t))
	main.fx = keep
