class_name RepairService
extends RefCounted
## 修復（V0.7：全部免費）。
## - 城牆與樹樁門：只靠樹屋修復鈕（HouseService）或精靈靈魂的修復之光。
## - 其他建築：存活精靈靠近手動修，或靈魂修。
## - 修繕站：範圍內 +25%，不疊加。
## - 威嚇怒吼：建築在暫停期間不能被修，之後一段時間修復量 -30%。

var sim: MatchSim


func _init(s: MatchSim) -> void:
	sim = s


static func is_wall_like(def_id: String) -> bool:
	return def_id == "wall" or def_id == "stump_gate"


## 這個單位能不能修這座建築（不看距離）。
func can_unit_repair(u: UnitState, inst: BuildingInstance) -> bool:
	if u == null or not u.on_map() or inst == null or not inst.is_alive() or inst.team_id != "elves":
		return false
	if sim.defs.get_def(inst.def_id).is_portal() or inst.hp >= inst.max_hp:
		return false
	if u.kind == UnitState.KIND_SOUL:
		return inst.is_functional() or sim.defs.get_def(inst.def_id).is_gate()
	if u.kind == UnitState.KIND_ELF:
		return inst.is_functional() and not is_wall_like(inst.def_id)
	return false


func repair_range() -> int:
	return int(sim.cfg["repair"]["range_cells"])


## 修繕站加成（%）：任一座完成的修繕站範圍涵蓋該點即生效，不疊加。
func aura_bonus_at(p: Vector2) -> int:
	var bonus := 0
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if not inst.is_functional():
			continue
		var aura: Dictionary = sim.defs.get_def(inst.def_id).level(inst.level).get("repair_aura", {})
		if not aura.is_empty() and inst.center().distance_to(p) <= float(aura["radius"]):
			bonus = maxi(bonus, int(aura["speed_bonus_percent"]))
	return bonus


## 以「每秒 hp_per_sec」修這座建築一個 tick。回傳實際恢復量。小數用千分位暫存，不會因捨去少修或多修。
func restore_tick(inst: BuildingInstance, hp_per_sec: int, bonus_percent: int) -> int:
	if inst.hp >= inst.max_hp or sim.tick < inst.repair_block_until:
		return 0
	var mult := 100 + bonus_percent
	if sim.tick < inst.repair_slow_until:
		mult = mult * (100 - inst.repair_slow_percent) / 100
	inst.repair_carry_milli += hp_per_sec * mult * 10 / sim.tick_rate
	var whole := inst.repair_carry_milli / 1000
	inst.repair_carry_milli -= whole * 1000
	whole = mini(whole, inst.max_hp - inst.hp)
	if whole <= 0:
		return 0
	inst.hp += whole
	if inst.state == BuildingInstance.ST_GATE_BROKEN and inst.hp >= inst.max_hp:
		sim.house.on_gate_repaired(inst)
	return whole


func start_repair(pid: int, iid: int) -> Dictionary:
	if sim.is_over():
		return {"ok": false, "reason": "match_over"}
	var p: PlayerAccount = sim.players.get(pid)
	if p == null:
		return {"ok": false, "reason": "invalid_player"}
	var u: UnitState = sim.units.get(p.unit_id)
	if u == null or not u.alive or (u.kind != UnitState.KIND_ELF and u.kind != UnitState.KIND_SOUL):
		return {"ok": false, "reason": "cannot_repair"}
	var inst: BuildingInstance = sim.buildings.get(iid)
	if inst and u.kind == UnitState.KIND_ELF and is_wall_like(inst.def_id):
		return {"ok": false, "reason": "walls_use_house_button"}
	if u.kind == UnitState.KIND_ELF and u.inside_house != -1:
		sim.house.exit_house(pid)
	if not can_unit_repair(u, inst):
		return {"ok": false, "reason": "not_repairable"}
	if u.kind == UnitState.KIND_ELF:
		p.job_instance_id = -1  # 修繕也是個人動作，會中斷施工
	sim.unit_svc.set_order(u, {"type": "repair", "instance_id": iid, "restored": 0})
	sim.events.emit_event("building_repair_started", {"player_id": pid, "instance_id": iid, "by": u.kind})
	return {"ok": true}


func tick_repairs() -> void:
	var uids := sim.units.keys()
	uids.sort()
	for uid in uids:
		var u: UnitState = sim.units[uid]
		if not u.alive or u.order.get("type") != "repair":
			continue
		var inst: BuildingInstance = sim.buildings.get(u.order["instance_id"])
		if inst == null or not inst.is_alive():
			_stop(u, "target_gone")
			continue
		if inst.hp >= inst.max_hp:
			_stop(u, "full")
			continue
		if not can_unit_repair(u, inst):
			continue
		if GridMath.cheb_cell_to_rect(u.cell(), inst.origin, inst.size) > repair_range():
			continue  # 還在走過去
		var rate := int(sim.cfg["repair"]["hp_per_sec"])
		if u.kind == UnitState.KIND_SOUL:
			var lv := int(u.soul_skills.get("repair", 1))
			rate = int(sim.cfg["soul"]["skills"]["repair"]["hp_per_sec"][lv - 1])
			var cost := float(sim.cfg["soul"]["repair_energy_per_sec"]) / sim.tick_rate
			if u.energy < cost:
				continue  # 能量不足：暫停，等回復
			u.energy -= cost
		var restored := restore_tick(inst, rate, aura_bonus_at(u.pos))
		u.order["restored"] = int(u.order.get("restored", 0)) + restored


func _stop(u: UnitState, why: String) -> void:
	sim.events.emit_event("building_repaired", {"unit_id": u.id, "instance_id": u.order.get("instance_id", -1), "restored": u.order.get("restored", 0), "stop_reason": why})
	sim.unit_svc.set_order(u, {"type": "idle"})
