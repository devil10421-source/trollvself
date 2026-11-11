class_name EscapeService
extends RefCounted
## 星界傳送門（V0.6）：團隊唯一、只能建在已被地形 + 城牆封閉的保護區內、三階段付費施工。
## 傳送門沒有 HP、不可被選為目標、不可被摧毀；巨魔的任何攻擊都不會影響施工進度。

const STATUS_NONE := ""
const STATUS_BUILDING := "building"
const STATUS_WAITING := "waiting_payment"   # 本階段完成，等待任一存活精靈支付下一階段
const STATUS_COMPLETE := "complete"
const PORTAL_STATE := "portal"

var sim: MatchSim
var portal_id := -1
var stage := 0
var status := STATUS_NONE
var progress_milli := 0
var required_milli := 0
var working := false
var builders := 0
var initiator := -1
var trolls_alerted := false
var revealed := false


func _init(s: MatchSim) -> void:
	sim = s


func def() -> BuildingDefinition:
	return sim.defs.get_def("escape_portal")


func portal_inst() -> BuildingInstance:
	return sim.buildings.get(portal_id)


func is_complete() -> bool:
	return status == STATUS_COMPLETE


func unlock_tick() -> int:
	return int(sim.cfg["portal_unlock_time_sec"]) * sim.tick_rate


func build_range() -> int:
	return int(sim.cfg["portal"]["build_range_cells"])


## 保護區是否已封閉：從巨魔出生區與所有巨魔方單位出發，在牆/建築/預定傳送門都視為阻擋時，
## 走不到任何保護區格 → 已封閉。
func zone_sealed(extra_blocked: Dictionary = {}) -> bool:
	var g: TileGrid = sim.grid
	var starts: Array = g.troll_spawn_cells.duplicate()
	for u in sim.units.values():
		var unit: UnitState = u
		if unit.alive and unit.spawned and unit.team == "trolls":
			starts.append(unit.cell())
	var seen := g.flood(starts, extra_blocked)
	for c in g.portal_zone_cells():
		if seen[g.idx(c)] == 1:
			return false
	return true


func validate_start(pid: int, origin: Vector2i) -> Dictionary:
	if sim.is_over():
		return {"ok": false, "reason": "match_over"}
	var p: PlayerAccount = sim.players.get(pid)
	if p == null or not p.alive_original:
		return {"ok": false, "reason": "not_living_elf"}
	if portal_id != -1:
		return {"ok": false, "reason": "portal_exists"}
	if sim.tick < unlock_tick():
		return {"ok": false, "reason": "time_locked", "detail": "%d 秒後開放" % ceili(float(unlock_tick() - sim.tick) / sim.tick_rate)}
	var d := def()
	var miss: String = sim.building_svc.missing_requirement(pid, d.requires)
	if miss != "":
		return {"ok": false, "reason": "requirement", "detail": miss}
	var cells := {}
	for c in GridMath.rect_cells(origin, d.footprint):
		if not sim.grid.is_portal_zone(c):
			return {"ok": false, "reason": "outside_portal_zone"}
		var prob: String = sim.building_svc.cell_problem(c)
		if prob != "":
			return {"ok": false, "reason": prob}
		cells[c] = true
	if sim.building_svc.unit_on_cells(cells):
		return {"ok": false, "reason": "unit_in_the_way"}
	if not zone_sealed(cells):
		return {"ok": false, "reason": "zone_not_sealed"}
	var u: UnitState = sim.building_svc.builder_unit(pid)
	if u == null:
		return {"ok": false, "reason": "no_builder"}
	var rng := build_range()
	var reach: Dictionary = sim.grid.bfs_path(u.cell(), func(c): return GridMath.cheb_cell_to_rect(c, origin, d.footprint) <= rng, cells)
	if not reach["found"]:
		return {"ok": false, "reason": "initiator_cannot_reach"}
	var st: Dictionary = d.stages[0]
	if not sim.economy.can_afford(pid, st["cost_g"], st["cost_w"]):
		return {"ok": false, "reason": "insufficient_resources"}
	return {"ok": true}


func start(pid: int, origin: Vector2i) -> Dictionary:
	var v := validate_start(pid, origin)
	if not v["ok"]:
		sim.events.emit_event("build_rejected", {"player_id": pid, "def_id": "escape_portal", "reason": v["reason"]})
		return v
	var d := def()
	var st: Dictionary = d.stages[0]
	if not sim.economy.spend(pid, st["cost_g"], st["cost_w"], "portal_stage_1"):
		return {"ok": false, "reason": "insufficient_resources"}
	var inst := BuildingInstance.new()
	inst.instance_id = sim.next_id()
	inst.def_id = d.id
	inst.owner_player_id = pid
	inst.team_id = "elves"
	inst.origin = origin
	inst.size = d.footprint
	inst.state = PORTAL_STATE
	inst.hp = 0
	inst.max_hp = 0
	sim.buildings[inst.instance_id] = inst
	sim.grid.occupy(origin, d.footprint, inst.instance_id)
	portal_id = inst.instance_id
	initiator = pid
	_begin_stage(1, pid)
	var u: UnitState = sim.building_svc.builder_unit(pid)
	if u:
		sim.players[pid].job_instance_id = -1
		sim.unit_svc.set_order(u, {"type": "portal_work"})
	return {"ok": true, "instance_id": inst.instance_id}


func validate_next_stage(pid: int) -> Dictionary:
	if sim.is_over():
		return {"ok": false, "reason": "match_over"}
	var p: PlayerAccount = sim.players.get(pid)
	if p == null or not p.alive_original:
		return {"ok": false, "reason": "not_living_elf"}
	if status != STATUS_WAITING:
		return {"ok": false, "reason": "not_waiting_for_payment"}
	var st: Dictionary = def().stages[stage]
	if not sim.economy.can_afford(pid, st["cost_g"], st["cost_w"]):
		return {"ok": false, "reason": "insufficient_resources"}
	return {"ok": true}


func next_stage(pid: int) -> Dictionary:
	var v := validate_next_stage(pid)
	if not v["ok"]:
		return v
	var st: Dictionary = def().stages[stage]
	if not sim.economy.spend(pid, st["cost_g"], st["cost_w"], "portal_stage_%d" % (stage + 1)):
		return {"ok": false, "reason": "insufficient_resources"}
	_begin_stage(stage + 1, pid)
	return {"ok": true}


func _begin_stage(n: int, pid: int) -> void:
	var st: Dictionary = def().stages[n - 1]
	stage = n
	status = STATUS_BUILDING
	progress_milli = 0
	required_milli = int(st["time_ticks"]) * 1000
	working = false
	sim.events.emit_event("escape_stage_started", {"stage": n, "player_id": pid})
	match str(st["reveal"]):
		"alert_trolls":
			trolls_alerted = true
			sim.events.emit_event("portal_alert_trolls", {})  # 不含座標
		"minimap_all":
			trolls_alerted = true
			revealed = true
			var inst := portal_inst()
			sim.events.emit_event("portal_revealed", {"origin": [inst.origin.x, inst.origin.y]})


func count_builders() -> int:
	var inst := portal_inst()
	if inst == null:
		return 0
	var n := 0
	for u in sim.units.values():
		var unit: UnitState = u
		if unit.on_map() and unit.kind == UnitState.KIND_ELF and sim.players[unit.player_id].alive_original:
			if GridMath.cheb_cell_to_rect(unit.cell(), inst.origin, inst.size) <= build_range():
				n += 1
	return n


func speed_bonus_percent(n: int) -> int:
	if n <= 1:
		return 0
	var per := int(sim.cfg["portal"]["bonus_per_extra_builder_percent"])
	return mini(int(sim.cfg["portal"]["max_bonus_percent"]), (n - 1) * per)


func tick() -> void:
	if status != STATUS_BUILDING:
		return
	builders = count_builders()
	if builders == 0:
		if working:
			working = false
			sim.events.emit_event("escape_stage_interrupted", {"stage": stage, "reason": "no_builders_in_range"})
		return
	if not working:
		working = true
		sim.events.emit_event("escape_stage_resumed", {"stage": stage, "builders": builders})
	progress_milli += 1000 + speed_bonus_percent(builders) * 10
	if progress_milli >= required_milli:
		progress_milli = required_milli
		working = false
		sim.events.emit_event("escape_stage_completed", {"stage": stage})
		if stage >= def().stages.size():
			status = STATUS_COMPLETE
		else:
			status = STATUS_WAITING


## 手機 UI 需要的狀態（不含 HP）。
func ui_status(pid: int) -> Dictionary:
	var d := def()
	var out := {"exists": portal_id != -1, "stage": stage, "stages": d.stages.size(), "status": status,
		"working": working, "builders": builders}
	if portal_id != -1 and status == STATUS_BUILDING:
		var rate := 1000 + speed_bonus_percent(maxi(1, builders)) * 10
		out["remaining_sec"] = float(required_milli - progress_milli) / rate / sim.tick_rate
		out["progress"] = float(progress_milli) / required_milli
	var next_idx := stage if portal_id != -1 else 0
	if next_idx < d.stages.size() and status != STATUS_BUILDING:
		var st: Dictionary = d.stages[next_idx]
		out["next_cost_g"] = st["cost_g"]
		out["next_cost_w"] = st["cost_w"]
		out["can_afford_next"] = sim.economy.can_afford(pid, st["cost_g"], st["cost_w"])
	if portal_id == -1:
		out["time_locked_sec"] = maxi(0, ceili(float(unlock_tick() - sim.tick) / sim.tick_rate))
		out["missing"] = sim.building_svc.missing_requirement(pid, d.requires)
	return out
