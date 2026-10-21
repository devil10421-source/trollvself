class_name RepairService
extends RefCounted
## 修繕：速率、跨 tick 付款、修繕站加速、靈魂修復授權。
##
## 計價：完整修復 = 累計實付成本 × 70%，按「恢復 HP / 最大 HP」等比例收費。
## 為了不讓逐 tick 捨去產生免費回血，採「整枚預付、餘額記帳」：
##   每點 HP 的價格分子 = 累計成本 × 70，一枚錢幣 = 100 × 最大 HP 個分子單位；
##   不夠時先向付款人收整枚錢幣存進該建築的預付餘額，再扣本次需要的分子。
##   餘額歸付款人所有、只用在同一座建築；建築升級後歸零（只會讓精靈多付，不會少付）。

var sim: MatchSim


func _init(s: MatchSim) -> void:
	sim = s


func can_be_repaired(inst: BuildingInstance) -> bool:
	return inst != null and inst.is_functional() and inst.hp < inst.max_hp and inst.team_id == "elves"


func repair_range() -> int:
	return int(sim.cfg["repair"]["range_cells"])


## 每 tick 的修繕量（整數 HP）。修繕站：任一座完成的修繕站範圍內 +25%，不疊加。
func hp_per_tick(unit: UnitState, base_hp_per_sec: int) -> int:
	var bonus := 0
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if not inst.is_functional():
			continue
		var aura: Dictionary = sim.defs.get_def(inst.def_id).level(inst.level).get("repair_aura", {})
		if aura.is_empty():
			continue
		if inst.center().distance_to(unit.pos) <= float(aura["radius"]):
			bonus = maxi(bonus, int(aura["speed_bonus_percent"]))
	var per_sec := base_hp_per_sec * (100 + bonus) / 100
	return maxi(1, per_sec / sim.tick_rate)


## 試著修 hp 點並向 payer 收費。回傳實際恢復量；資源不足回傳 0（完全不修、不扣）。
func pay_and_restore(inst: BuildingInstance, payer_id: int, hp: int) -> int:
	hp = mini(hp, inst.max_hp - inst.hp)
	if hp <= 0:
		return 0
	var ratio := int(sim.cfg["repair"]["cost_ratio_percent"])
	var denom := 100 * inst.max_hp
	var need_g := hp * inst.total_paid_g * ratio
	var need_w := hp * inst.total_paid_w * ratio
	var credit: Dictionary = inst.repair_credit.get(payer_id, {"g": 0, "w": 0})
	var coins_g := _coins_needed(need_g - int(credit["g"]), denom)
	var coins_w := _coins_needed(need_w - int(credit["w"]), denom)
	if not sim.economy.spend(payer_id, coins_g, coins_w, "repair"):
		return 0
	credit["g"] = int(credit["g"]) + coins_g * denom - need_g
	credit["w"] = int(credit["w"]) + coins_w * denom - need_w
	inst.repair_credit[payer_id] = credit
	inst.hp += hp
	return hp


static func _coins_needed(shortfall: int, denom: int) -> int:
	if shortfall <= 0:
		return 0
	return (shortfall + denom - 1) / denom


## 找一位已開啟授權、且是存活原始精靈的付款人（依玩家 ID 順序）。
func soul_payer() -> int:
	var ids := sim.players.keys()
	ids.sort()
	for pid in ids:
		var p: PlayerAccount = sim.players[pid]
		if p.alive_original and p.authorize_soul_repair:
			return pid
	return -1


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
	if not can_be_repaired(inst):
		return {"ok": false, "reason": "not_repairable"}
	if u.kind == UnitState.KIND_SOUL and soul_payer() == -1:
		return {"ok": false, "reason": "no_authorized_payer"}
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
		if not inst.is_functional():
			continue
		if GridMath.cheb_cell_to_rect(u.cell(), inst.origin, inst.size) > repair_range():
			continue  # 還在走過去
		var payer := u.player_id
		var base := int(sim.cfg["repair"]["hp_per_sec"])
		if u.kind == UnitState.KIND_SOUL:
			payer = soul_payer()
			if payer == -1:
				_stop(u, "no_authorized_payer")
				continue
			base = int(sim.cfg["soul"]["repair_hp_per_sec"])
			var cost := float(sim.cfg["soul"]["repair_energy_per_sec"]) / sim.tick_rate
			if u.energy < cost:
				continue  # 能量不足：暫停，等回復
			u.energy -= cost
		elif not sim.players[payer].alive_original:
			_stop(u, "payer_dead")
			continue
		var restored := pay_and_restore(inst, payer, hp_per_tick(u, base))
		if restored > 0:
			u.order["restored"] = int(u.order.get("restored", 0)) + restored
		else:
			_stop(u, "insufficient_resources")


func _stop(u: UnitState, why: String) -> void:
	sim.events.emit_event("building_repaired", {"unit_id": u.id, "instance_id": u.order.get("instance_id", -1), "restored": u.order.get("restored", 0), "stop_reason": why})
	sim.unit_svc.set_order(u, {"type": "idle"})
