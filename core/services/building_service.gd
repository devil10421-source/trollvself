class_name BuildingService
extends RefCounted
## 放置合法性、建造、升級、取消、拆除、占格、施工推進與完工事件（不含傳送門，見 EscapeService）。

var sim: MatchSim


func _init(s: MatchSim) -> void:
	sim = s


# ---------- 查詢 ----------

## 擁有者某種建築的最高「已完成」等級（施工中 = 0；升級中仍算舊等級）。
func owner_level(pid: int, def_id: String) -> int:
	var best := 0
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if inst.owner_player_id == pid and inst.def_id == def_id and inst.is_alive():
			best = maxi(best, inst.level)
	return best


func count_owned(pid: int, def_id: String) -> int:
	var n := 0
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if inst.owner_player_id == pid and inst.def_id == def_id and inst.is_alive():
			n += 1
	return n


## 回傳第一個未滿足的前置（給 UI 顯示），全部滿足回傳 ""。
func missing_requirement(pid: int, reqs: Array) -> String:
	for r in reqs:
		if owner_level(pid, r["building"]) < int(r["level"]):
			var d: BuildingDefinition = sim.defs.get_def(r["building"])
			return "需要%s Lv%d" % [d.display_name if d else r["building"], r["level"]]
	return ""


func builder_unit(pid: int) -> UnitState:
	var p: PlayerAccount = sim.players.get(pid)
	if p == null:
		return null
	var u: UnitState = sim.units.get(p.unit_id)
	if u == null or not u.alive or not u.is_original_elf():
		return null
	return u


func builder_range() -> int:
	return int(sim.cfg["construction"]["builder_range_cells"])


func unit_on_cells(cells: Dictionary) -> bool:
	for u in sim.units.values():
		var unit: UnitState = u
		if unit.on_map() and cells.has(unit.cell()):
			return true
	return false


## 檢查單一格能否當作占格（給預覽與放置共用）。
func cell_problem(c: Vector2i) -> String:
	var g: TileGrid = sim.grid
	if not g.in_bounds(c):
		return "out_of_bounds"
	if g.is_terrain_blocked(c):
		return "blocked_terrain"
	if g.stump_gate_cells.has(c):
		return "gate_cell"
	if g.no_build[g.idx(c)] == 1:
		return "spawn_area"
	if g.occupancy.has(c):
		return "occupied"
	return ""


# ---------- 放置 ----------

func validate_place(pid: int, def_id: String, origin: Vector2i) -> Dictionary:
	if sim.is_over():
		return {"ok": false, "reason": "match_over"}
	var p: PlayerAccount = sim.players.get(pid)
	if p == null or not p.alive_original:
		return {"ok": false, "reason": "not_living_elf"}
	var d: BuildingDefinition = sim.defs.get_def(def_id)
	if d == null:
		return {"ok": false, "reason": "unknown_building"}
	if d.is_portal():
		return {"ok": false, "reason": "use_portal_start"}
	if not d.buildable:
		return {"ok": false, "reason": "not_buildable"}
	if d.max_per_player > 0 and count_owned(pid, def_id) >= d.max_per_player:
		return {"ok": false, "reason": "limit_reached"}
	var lv1 := d.level(1)
	var miss := missing_requirement(pid, lv1["requires"])
	if miss != "":
		return {"ok": false, "reason": "requirement", "detail": miss}
	var cells := {}
	for c in GridMath.rect_cells(origin, d.footprint):
		var prob := cell_problem(c)
		if prob != "":
			return {"ok": false, "reason": prob}
		cells[c] = true
	if unit_on_cells(cells):
		return {"ok": false, "reason": "unit_in_the_way"}
	var u := builder_unit(pid)
	if u == null:
		return {"ok": false, "reason": "no_builder"}
	var rng := builder_range()
	var reach: Dictionary = sim.grid.bfs_path(u.cell(), func(c): return GridMath.cheb_cell_to_rect(c, origin, d.footprint) <= rng, cells)
	if not reach["found"]:
		return {"ok": false, "reason": "builder_cannot_reach"}
	if not sim.economy.can_afford(pid, lv1["cost_g"], lv1["cost_w"]):
		return {"ok": false, "reason": "insufficient_resources"}
	return {"ok": true}


func place(pid: int, def_id: String, origin: Vector2i) -> Dictionary:
	sim.events.emit_event("build_requested", {"player_id": pid, "def_id": def_id, "origin": [origin.x, origin.y]})
	var v := validate_place(pid, def_id, origin)
	if not v["ok"]:
		sim.events.emit_event("build_rejected", {"player_id": pid, "def_id": def_id, "reason": v["reason"]})
		return v
	var d: BuildingDefinition = sim.defs.get_def(def_id)
	var lv1 := d.level(1)
	if not sim.economy.spend(pid, lv1["cost_g"], lv1["cost_w"], "build:" + def_id):
		return {"ok": false, "reason": "insufficient_resources"}
	var inst := BuildingInstance.new()
	inst.instance_id = sim.next_id()
	inst.def_id = def_id
	inst.owner_player_id = pid
	inst.team_id = "elves"
	inst.origin = origin
	inst.size = d.footprint
	inst.level = 0
	inst.state = BuildingInstance.ST_CONSTRUCTING
	inst.max_hp = lv1["hp"]
	inst.construction_start_hp = maxi(1, inst.max_hp * int(sim.cfg["construction"]["start_hp_percent"]) / 100)
	inst.hp = inst.construction_start_hp
	inst.job_target_level = 1
	inst.job_required_ticks = lv1["time_ticks"]
	inst.job_paid_g = lv1["cost_g"]
	inst.job_paid_w = lv1["cost_w"]
	sim.buildings[inst.instance_id] = inst
	sim.grid.occupy(origin, d.footprint, inst.instance_id)
	sim.events.emit_event("build_started", {"player_id": pid, "instance_id": inst.instance_id, "def_id": def_id, "origin": [origin.x, origin.y]})
	assign_job(pid, inst.instance_id)
	return {"ok": true, "instance_id": inst.instance_id}


# ---------- 升級 / 取消 / 拆除 ----------

func validate_upgrade(pid: int, iid: int) -> Dictionary:
	if sim.is_over():
		return {"ok": false, "reason": "match_over"}
	var p: PlayerAccount = sim.players.get(pid)
	if p == null or not p.alive_original:
		return {"ok": false, "reason": "not_living_elf"}
	var inst: BuildingInstance = sim.buildings.get(iid)
	if inst == null or not inst.is_alive():
		return {"ok": false, "reason": "no_such_building"}
	if inst.owner_player_id != pid:
		return {"ok": false, "reason": "not_owner"}
	var d: BuildingDefinition = sim.defs.get_def(inst.def_id)
	if d.is_portal():
		return {"ok": false, "reason": "use_portal_next_stage"}
	if not d.buildable:
		return {"ok": false, "reason": "not_buildable"}
	if inst.state != BuildingInstance.ST_ACTIVE:
		return {"ok": false, "reason": "busy"}
	if inst.level >= d.max_level():
		return {"ok": false, "reason": "max_level"}
	var nxt := d.level(inst.level + 1)
	var miss := missing_requirement(pid, nxt["requires"])
	if miss != "":
		return {"ok": false, "reason": "requirement", "detail": miss}
	if not sim.economy.can_afford(pid, nxt["cost_g"], nxt["cost_w"]):
		return {"ok": false, "reason": "insufficient_resources"}
	return {"ok": true}


func upgrade(pid: int, iid: int) -> Dictionary:
	var v := validate_upgrade(pid, iid)
	if not v["ok"]:
		return v
	var inst: BuildingInstance = sim.buildings[iid]
	var nxt := sim.defs.get_def(inst.def_id).level(inst.level + 1)
	if not sim.economy.spend(pid, nxt["cost_g"], nxt["cost_w"], "upgrade:" + inst.def_id):
		return {"ok": false, "reason": "insufficient_resources"}
	inst.state = BuildingInstance.ST_UPGRADING
	inst.job_target_level = inst.level + 1
	inst.job_progress_ticks = 0
	inst.job_required_ticks = nxt["time_ticks"]
	inst.job_paid_g = nxt["cost_g"]
	inst.job_paid_w = nxt["cost_w"]
	sim.events.emit_event("upgrade_started", {"player_id": pid, "instance_id": iid, "to_level": inst.job_target_level})
	assign_job(pid, iid)
	return {"ok": true}


## 取消未完工的建造或升級：退還「未施工剩餘比例 × 已付成本 × 退款%」，一律無條件捨去。
func cancel(pid: int, iid: int) -> Dictionary:
	var inst: BuildingInstance = sim.buildings.get(iid)
	if inst == null or not inst.is_alive():
		return {"ok": false, "reason": "no_such_building"}
	if inst.owner_player_id != pid:
		return {"ok": false, "reason": "not_owner"}
	if sim.defs.get_def(inst.def_id).is_portal():
		return {"ok": false, "reason": "portal_not_cancellable"}
	if not inst.has_job():
		return {"ok": false, "reason": "nothing_to_cancel"}
	var pct := int(sim.cfg["construction"]["cancel_refund_percent"])
	var refund := refund_for_cancel(inst, pct)
	sim.economy.grant(pid, refund[0], refund[1], "cancel_refund")
	_release_job(inst)
	if inst.state == BuildingInstance.ST_CONSTRUCTING:
		_remove(inst)
		sim.events.emit_event("building_cancelled", {"player_id": pid, "instance_id": iid, "refund_g": refund[0], "refund_w": refund[1]})
	else:
		inst.state = BuildingInstance.ST_ACTIVE
		_clear_job_fields(inst)
		sim.events.emit_event("upgrade_cancelled", {"player_id": pid, "instance_id": iid, "refund_g": refund[0], "refund_w": refund[1]})
	return {"ok": true, "refund_g": refund[0], "refund_w": refund[1]}


func refund_for_cancel(inst: BuildingInstance, pct: int) -> Array:
	var rem := inst.remaining_job_ticks()
	var req := maxi(1, inst.job_required_ticks)
	return [inst.job_paid_g * rem * pct / (req * 100), inst.job_paid_w * rem * pct / (req * 100)]


func demolish(pid: int, iid: int) -> Dictionary:
	var inst: BuildingInstance = sim.buildings.get(iid)
	if inst == null or not inst.is_alive():
		return {"ok": false, "reason": "no_such_building"}
	if inst.owner_player_id != pid:
		return {"ok": false, "reason": "not_owner"}
	if sim.defs.get_def(inst.def_id).is_portal():
		return {"ok": false, "reason": "portal_not_demolishable"}
	if not sim.defs.get_def(inst.def_id).buildable:
		return {"ok": false, "reason": "not_demolishable"}
	if inst.state != BuildingInstance.ST_ACTIVE:
		return {"ok": false, "reason": "cancel_job_first"}
	var pct := int(sim.cfg["construction"]["demolish_refund_percent"])
	sim.economy.grant(pid, inst.total_paid_g * pct / 100, inst.total_paid_w * pct / 100, "demolish_refund")
	if inst.def_id == "elf_house":
		sim.house.on_house_destroyed(inst, false)
	_remove(inst)
	if inst.def_id == "elf_house":
		sim.house.refresh_gate_hp(pid)
	sim.events.emit_event("building_demolished", {"player_id": pid, "instance_id": iid})
	return {"ok": true}


# ---------- 施工 ----------

## 指派個人施工動作（會中斷該精靈原本的施工；舊工地保持暫停，可再指派續建）。
func assign_job(pid: int, iid: int) -> Dictionary:
	var p: PlayerAccount = sim.players.get(pid)
	var inst: BuildingInstance = sim.buildings.get(iid)
	if p == null or not p.alive_original:
		return {"ok": false, "reason": "not_living_elf"}
	if inst == null or not inst.has_job() or inst.owner_player_id != pid:
		return {"ok": false, "reason": "no_job_here"}
	p.job_instance_id = iid
	var u := builder_unit(pid)
	if u and u.inside_house != -1:
		sim.house.exit_house(pid)
	if u:
		sim.unit_svc.set_order(u, {"type": "build", "instance_id": iid})
	return {"ok": true}


func is_builder_present(inst: BuildingInstance) -> bool:
	var p: PlayerAccount = sim.players.get(inst.owner_player_id)
	if p == null or not p.alive_original or p.job_instance_id != inst.instance_id:
		return false
	var u := builder_unit(p.id)
	if u == null or not u.on_map() or u.order.get("type") != "build" or u.order.get("instance_id") != inst.instance_id:
		return false
	if sim.tick < u.build_block_until:
		return false
	return GridMath.cheb_cell_to_rect(u.cell(), inst.origin, inst.size) <= builder_range()


func tick_jobs() -> void:
	var ids := sim.buildings.keys()
	ids.sort()
	for iid in ids:
		var inst: BuildingInstance = sim.buildings.get(iid)
		if inst == null or not inst.has_job():
			continue
		if not is_builder_present(inst):
			continue
		inst.job_progress_ticks += 1
		if inst.state == BuildingInstance.ST_CONSTRUCTING:
			var grow := (inst.max_hp - inst.construction_start_hp) * inst.job_progress_ticks / inst.job_required_ticks
			inst.hp = clampi(inst.construction_start_hp + grow - inst.construction_damage, 1, inst.max_hp)
		if inst.job_progress_ticks >= inst.job_required_ticks:
			_complete_job(inst)


func _complete_job(inst: BuildingInstance) -> void:
	var d: BuildingDefinition = sim.defs.get_def(inst.def_id)
	var new_lv := d.level(inst.job_target_level)
	inst.total_paid_g += inst.job_paid_g
	inst.total_paid_w += inst.job_paid_w
	if inst.state == BuildingInstance.ST_CONSTRUCTING:
		inst.level = 1
		inst.hp = clampi(inst.max_hp - inst.construction_damage, 1, inst.max_hp)
		inst.state = BuildingInstance.ST_ACTIVE
		_release_job(inst)
		_clear_job_fields(inst)
		sim.events.emit_event("building_completed", {"instance_id": inst.instance_id, "def_id": inst.def_id, "owner": inst.owner_player_id})
	else:
		var old_max := inst.max_hp
		inst.level = inst.job_target_level
		inst.max_hp = new_lv["hp"]
		if sim.cfg["construction"].get("keep_hp_ratio_on_upgrade", true):
			inst.hp = clampi(inst.hp * inst.max_hp / maxi(1, old_max), 1, inst.max_hp)
		inst.repair_carry_milli = 0
		inst.state = BuildingInstance.ST_ACTIVE
		_release_job(inst)
		_clear_job_fields(inst)
		sim.events.emit_event("building_upgraded", {"instance_id": inst.instance_id, "def_id": inst.def_id, "level": inst.level})
	if inst.def_id == "elf_house":
		sim.house.refresh_gate_hp(inst.owner_player_id)


func _clear_job_fields(inst: BuildingInstance) -> void:
	inst.job_target_level = 0
	inst.job_progress_ticks = 0
	inst.job_required_ticks = 0
	inst.job_paid_g = 0
	inst.job_paid_w = 0


func _release_job(inst: BuildingInstance) -> void:
	for p in sim.players.values():
		var pa: PlayerAccount = p
		if pa.job_instance_id == inst.instance_id:
			pa.job_instance_id = -1
	for u in sim.units.values():
		var unit: UnitState = u
		if unit.order.get("instance_id", -1) == inst.instance_id and unit.order.get("type") == "build":
			sim.unit_svc.set_order(unit, {"type": "idle"})


func _remove(inst: BuildingInstance) -> void:
	_release_job(inst)
	for u in sim.units.values():
		var unit: UnitState = u
		if unit.order.get("instance_id", -1) == inst.instance_id:
			sim.unit_svc.set_order(unit, {"type": "idle"})
	inst.state = BuildingInstance.ST_DESTROYED
	sim.grid.vacate(inst.origin, inst.size)
	sim.buildings.erase(inst.instance_id)


## 被巨魔摧毀。既有其他建築不受影響（不倒退）。
func destroy(inst: BuildingInstance, attacker_unit_id: int) -> void:
	if not inst.is_alive():
		return
	if inst.def_id == "elf_house":
		sim.house.on_house_destroyed(inst)
	_remove(inst)
	if inst.def_id == "elf_house":
		sim.house.refresh_gate_hp(inst.owner_player_id)
	sim.events.emit_event("building_destroyed", {"instance_id": inst.instance_id, "def_id": inst.def_id, "owner": inst.owner_player_id, "attacker_unit_id": attacker_unit_id})
