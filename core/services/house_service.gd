class_name HouseService
extends RefCounted
## V0.7 精靈的樹屋玩法：
## - 入屋：精靈走進自己的樹屋後從地圖消失、不可被選為目標，樹屋金幣 +50%。
## - 樹樁門：每個基地入口一扇（地圖 D 格）。擁有者在屋內時關門，擋巨魔也擋精靈；
##   可被打破，打破後保持開啟，直到被修滿。HP 依擁有者樹屋等級。
## - 修復鈕：點樹屋按「修復」，接下來 3 秒修自己基地裡 HP 比例最低的城牆或樹樁門；
##   冷卻從按下起算，速度與冷卻依樹屋等級。完全免費。

var sim: MatchSim
var gate_ids: Array[int] = []


func _init(s: MatchSim) -> void:
	sim = s


# ---------- 樹樁門 ----------

## 開局時依地圖 D 格建立門，擁有者 = 最近的精靈出生點。
func create_gates() -> void:
	var d: BuildingDefinition = sim.defs.get_def("stump_gate")
	for g in sim.grid.stump_gate_groups():
		var origin: Vector2i = g["origin"]
		var size: Vector2i = g["size"]
		var owner := _nearest_elf_spawn(GridMath.rect_center(origin, size))
		var inst := BuildingInstance.new()
		inst.instance_id = sim.next_id()
		inst.def_id = d.id
		inst.owner_player_id = owner
		inst.team_id = "elves"
		inst.origin = origin
		inst.size = size
		inst.level = 1
		inst.state = BuildingInstance.ST_GATE_OPEN
		inst.max_hp = gate_hp_for(owner)
		inst.hp = inst.max_hp
		sim.buildings[inst.instance_id] = inst
		gate_ids.append(inst.instance_id)


func _nearest_elf_spawn(p: Vector2) -> int:
	var best := -1
	var bd := 1e9
	for pid in sim.grid.elf_spawns:
		var d := p.distance_to(GridMath.cell_center(sim.grid.elf_spawns[pid]))
		if d < bd and sim.players.has(pid):
			bd = d
			best = pid
	return best


func gate_of(pid: int) -> BuildingInstance:
	for gid in gate_ids:
		var g: BuildingInstance = sim.buildings.get(gid)
		if g and g.owner_player_id == pid:
			return g
	return null


func gate_hp_for(pid: int) -> int:
	var table: Array = sim.cfg["gate"]["hp_by_house_level"]
	return int(table[clampi(house_level(pid), 0, table.size() - 1)])


## 樹屋升級或被毀後，門的最大 HP 跟著變（保留血量比例）。
func refresh_gate_hp(pid: int) -> void:
	var g := gate_of(pid)
	if g == null:
		return
	var new_max := gate_hp_for(pid)
	if new_max == g.max_hp:
		return
	g.hp = clampi(g.hp * new_max / maxi(1, g.max_hp), 0, new_max)
	if g.state != BuildingInstance.ST_GATE_BROKEN:
		g.hp = maxi(1, g.hp)
	g.max_hp = new_max


func is_closed(g: BuildingInstance) -> bool:
	return g != null and g.state == BuildingInstance.ST_GATE_CLOSED


func _set_gate_state(g: BuildingInstance, st: String) -> void:
	if g.state == st:
		return
	var was_closed := g.state == BuildingInstance.ST_GATE_CLOSED
	g.state = st
	if st == BuildingInstance.ST_GATE_CLOSED:
		sim.grid.occupy(g.origin, g.size, g.instance_id)
	elif was_closed:
		sim.grid.vacate(g.origin, g.size)
	sim.events.emit_event("gate_changed", {"instance_id": g.instance_id, "owner": g.owner_player_id, "state": st})


## 被打到 0 HP：打破，保持開啟。
func break_gate(g: BuildingInstance, attacker_unit_id: int) -> void:
	g.hp = 0
	_set_gate_state(g, BuildingInstance.ST_GATE_BROKEN)
	sim.events.emit_event("gate_broken", {"instance_id": g.instance_id, "owner": g.owner_player_id, "attacker_unit_id": attacker_unit_id})


func on_gate_repaired(g: BuildingInstance) -> void:
	_set_gate_state(g, BuildingInstance.ST_GATE_OPEN)
	sim.events.emit_event("gate_restored", {"instance_id": g.instance_id})


## 每 tick：擁有者在屋內 → 關門（門口有人站著就等他離開）；不在 → 開門。
func tick_gates() -> void:
	for gid in gate_ids:
		var g: BuildingInstance = sim.buildings.get(gid)
		if g == null or g.state == BuildingInstance.ST_GATE_BROKEN:
			continue
		var want_closed := is_inside(g.owner_player_id)
		if want_closed and g.state == BuildingInstance.ST_GATE_OPEN:
			var cells := {}
			for c in GridMath.rect_cells(g.origin, g.size):
				cells[c] = true
			if not sim.building_svc.unit_on_cells(cells):
				_set_gate_state(g, BuildingInstance.ST_GATE_CLOSED)
		elif not want_closed and g.state == BuildingInstance.ST_GATE_CLOSED:
			_set_gate_state(g, BuildingInstance.ST_GATE_OPEN)


# ---------- 入屋 / 出屋 ----------

func house_of(pid: int) -> BuildingInstance:
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if inst.owner_player_id == pid and inst.def_id == "elf_house" and inst.is_alive():
			return inst
	return null


func house_level(pid: int) -> int:
	var h := house_of(pid)
	return h.level if h else 0


func is_inside(pid: int) -> bool:
	var p: PlayerAccount = sim.players.get(pid)
	if p == null or not p.alive_original:
		return false
	var u: UnitState = sim.units.get(p.unit_id)
	return u != null and u.alive and u.inside_house != -1


func enter_range() -> int:
	return int(sim.cfg["house"]["enter_range_cells"])


## 在自己的樹屋內時，可以遠端建造／升級樹屋附近（自己基地內）的建築。
## 這是參考《猛鬼宿舍》躺床蓋東西的做法；match_config 的 house.build_from_inside 可關掉。
func can_build_remotely(pid: int, inst: BuildingInstance) -> bool:
	if not bool(sim.cfg["house"].get("build_from_inside", false)) or not is_inside(pid):
		return false
	var h := house_of(pid)
	if h == null or not h.is_functional() or inst == null:
		return false
	return GridMath.point_to_rect(h.center(), inst.origin, inst.size) <= float(sim.cfg["house"]["remote_build_radius"])


## 下令：走到自己的樹屋旁，到了就進去。
func command_enter(pid: int) -> Dictionary:
	if sim.is_over():
		return {"ok": false, "reason": "match_over"}
	var p: PlayerAccount = sim.players.get(pid)
	if p == null or not p.alive_original:
		return {"ok": false, "reason": "not_living_elf"}
	var u: UnitState = sim.units.get(p.unit_id)
	if u == null or not u.alive:
		return {"ok": false, "reason": "no_unit"}
	if u.inside_house != -1:
		return {"ok": false, "reason": "already_inside"}
	var h := house_of(pid)
	if h == null or not h.is_functional():
		return {"ok": false, "reason": "no_house"}
	p.job_instance_id = -1
	sim.unit_svc.set_order(u, {"type": "enter_house", "instance_id": h.instance_id})
	return {"ok": true}


## 由 UnitService 在單位走到樹屋旁時呼叫。
func do_enter(u: UnitState, h: BuildingInstance) -> void:
	u.inside_house = h.instance_id
	u.pos = h.center()
	u.path = []
	u.order = {"type": "idle"}
	sim.events.emit_event("house_entered", {"player_id": u.player_id, "instance_id": h.instance_id})


func exit_house(pid: int) -> Dictionary:
	var p: PlayerAccount = sim.players.get(pid)
	if p == null:
		return {"ok": false, "reason": "invalid_player"}
	var u: UnitState = sim.units.get(p.unit_id)
	if u == null or u.inside_house == -1:
		return {"ok": false, "reason": "not_inside"}
	_place_outside(u, sim.buildings.get(u.inside_house))
	sim.events.emit_event("house_exited", {"player_id": pid})
	return {"ok": true}


func _place_outside(u: UnitState, h: BuildingInstance) -> void:
	var start := u.cell()
	if h:
		start = h.origin
	u.inside_house = -1
	var r: Dictionary = sim.grid.bfs_path(start, func(c): return sim.grid.is_walkable(c))
	if r["found"] and not r["path"].is_empty():
		u.pos = GridMath.cell_center(r["path"][-1])
	elif sim.grid.is_walkable(start):
		u.pos = GridMath.cell_center(start)
	u.path = []


## 樹屋被摧毀：屋內精靈被彈出並暈眩；拆除時不暈眩。
func on_house_destroyed(h: BuildingInstance, stun: bool = true) -> void:
	for v in sim.units.values():
		var u: UnitState = v
		if u.inside_house == h.instance_id:
			# 先騰出占格再找落點，彈到樹屋原位附近
			sim.grid.vacate(h.origin, h.size)
			_place_outside(u, h)
			u.pos = GridMath.cell_center(h.origin)
			if stun:
				u.stunned_until = sim.tick + sim.defs.sec_to_ticks(float(sim.cfg["house"]["eject_stun_sec"]))
			sim.events.emit_event("house_ejected", {"player_id": u.player_id})


## 經濟：入屋的金幣加成（無條件捨去）。
func gold_with_bonus(owner_id: int, house: BuildingInstance, base_gold: int) -> int:
	var p: PlayerAccount = sim.players.get(owner_id)
	if p == null:
		return base_gold
	var u: UnitState = sim.units.get(p.unit_id)
	if u and u.alive and u.inside_house == house.instance_id:
		return base_gold * (100 + int(sim.cfg["house"]["inside_gold_bonus_percent"])) / 100
	return base_gold


# ---------- 修復鈕 ----------

func repair_params(level: int) -> Dictionary:
	var lv: Array = sim.cfg["house"]["repair_button"]["levels"]
	return lv[clampi(level, 1, lv.size()) - 1]


func repair_cooldown_left_sec(pid: int) -> float:
	var p: PlayerAccount = sim.players.get(pid)
	if p == null:
		return 0.0
	return maxf(0.0, float(p.house_repair_ready - sim.tick) / sim.tick_rate)


func repair_cooldown_total_sec(pid: int) -> float:
	return float(repair_params(maxi(1, house_level(pid)))["cooldown_sec"])


func repair_active(pid: int) -> bool:
	var p: PlayerAccount = sim.players.get(pid)
	return p != null and sim.tick <= p.house_repair_until and p.house_repair_until >= 0


func press_repair(pid: int) -> Dictionary:
	if sim.is_over():
		return {"ok": false, "reason": "match_over"}
	var p: PlayerAccount = sim.players.get(pid)
	if p == null or not p.alive_original:
		return {"ok": false, "reason": "not_living_elf"}
	var h := house_of(pid)
	if h == null or not h.is_functional():
		return {"ok": false, "reason": "no_house"}
	if sim.tick < p.house_repair_ready:
		return {"ok": false, "reason": "cooldown", "detail": "%.1f 秒" % repair_cooldown_left_sec(pid)}
	var prm := repair_params(h.level)
	p.house_repair_until = sim.tick + sim.defs.sec_to_ticks(float(sim.cfg["house"]["repair_button"]["duration_sec"]))
	p.house_repair_ready = sim.tick + sim.defs.sec_to_ticks(float(prm["cooldown_sec"]))
	sim.events.emit_event("house_repair_pressed", {"player_id": pid, "level": h.level})
	return {"ok": true}


## 自己基地 = 自己擁有的城牆 + 自己的樹樁門。挑 HP 比例最低、還沒滿的。
func repair_target(pid: int) -> BuildingInstance:
	var best: BuildingInstance = null
	var best_ratio := 2.0
	var ids := sim.buildings.keys()
	ids.sort()
	for bid in ids:
		var inst: BuildingInstance = sim.buildings[bid]
		if inst.owner_player_id != pid or inst.hp >= inst.max_hp:
			continue
		if inst.def_id == "wall":
			if not inst.is_functional():
				continue
		elif inst.def_id != "stump_gate":
			continue
		if sim.tick < inst.repair_block_until:
			continue
		var ratio := float(inst.hp) / maxf(1.0, inst.max_hp)
		if ratio < best_ratio:
			best_ratio = ratio
			best = inst
	return best


func tick_repairs() -> void:
	var ids := sim.players.keys()
	ids.sort()
	for pid in ids:
		var p: PlayerAccount = sim.players[pid]
		if not p.alive_original or sim.tick > p.house_repair_until:
			continue
		var h := house_of(pid)
		if h == null or not h.is_functional():
			p.house_repair_until = -1
			continue
		var target := repair_target(pid)
		if target == null:
			continue
		var bonus := 0
		if sim.cfg["repair"].get("repair_post_applies_to_house_button", true):
			bonus = sim.repair.aura_bonus_at(target.center())
		sim.repair.restore_tick(target, int(repair_params(h.level)["hp_per_sec"]), bonus)
