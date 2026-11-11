class_name CombatService
extends RefCounted
## 建築受傷、HP 扣除、傷害防護、塔選敵與巨魔收益事件。
## V0.6：傳送門（targetable_by_enemies=false / damageable=false）在這裡被絕對排除。

var sim: MatchSim


func _init(s: MatchSim) -> void:
	sim = s


## 伺服器端判定：這座建築能不能被敵方選為攻擊目標。
func is_attackable_building(inst: BuildingInstance) -> bool:
	if inst == null or not inst.is_alive() or inst.team_id != "elves":
		return false
	var d: BuildingDefinition = sim.defs.get_def(inst.def_id)
	if d.is_gate():
		return inst.state == BuildingInstance.ST_GATE_CLOSED  # 開著或已破的門沒有東西可打
	return d.targetable_by_enemies and d.damageable


## 對建築造成傷害。回傳「實際有效扣除的 HP」。收益只按這個數字發放。
func damage_building(attacker: UnitState, inst: BuildingInstance, amount: int) -> int:
	if amount <= 0 or not is_attackable_building(inst):
		return 0
	var effective := mini(amount, inst.hp)
	if effective <= 0:
		return 0
	inst.hp -= effective
	if inst.state == BuildingInstance.ST_CONSTRUCTING:
		inst.construction_damage += effective
	if attacker:
		attacker.last_building_attack_tick = sim.tick
	sim.events.emit_event("building_damaged", {
		"instance_id": inst.instance_id, "def_id": inst.def_id, "amount": effective,
		"hp": inst.hp, "attacker_unit_id": attacker.id if attacker else -1,
	})
	_reward(attacker, effective)
	if attacker and attacker.team == "trolls":
		sim.troll.add_xp(int(effective * float(sim.cfg["troll"]["xp_per_effective_hp"])), "building_damage")
	if inst.hp <= 0:
		if sim.defs.get_def(inst.def_id).is_gate():
			sim.house.break_gate(inst, attacker.id if attacker else -1)
		else:
			sim.building_svc.destroy(inst, attacker.id if attacker else -1)
	return effective


## 巨魔方收益接口：依實際有效傷害累積，整數入帳。係數在 match_config（占位值）。
func _reward(attacker: UnitState, effective_hp: int) -> void:
	if attacker == null or attacker.team != "trolls" or attacker.reward_per_hp <= 0.0:
		return
	attacker.reward_carry += effective_hp * attacker.reward_per_hp
	var whole := int(floor(attacker.reward_carry))
	if whole > 0:
		attacker.reward_carry -= whole
		var p: PlayerAccount = sim.players.get(attacker.player_id)
		if p:
			p.troll_gold += whole
			sim.events.emit_event("troll_reward", {"player_id": p.id, "amount": whole, "total": p.troll_gold})


func damage_unit(attacker: UnitState, target: UnitState, amount: int) -> int:
	if target == null or not target.on_map() or amount <= 0:
		return 0
	if attacker and attacker.team == target.team:
		return 0
	if target.kind == UnitState.KIND_SOUL:
		return 0  # 靈魂不是可攻擊目標（控制/戰鬥技能留待技能規格）
	if target.team == "trolls":
		var pct := sim.troll.damage_taken_mult_percent(target)
		if attacker == null and sim.tick < target.marked_until:
			pct += target.marked_bonus  # 星光印記：塔的傷害加成
		amount = amount * pct / 100
	var effective := mini(amount, target.hp)
	target.hp -= effective
	if target.team == "trolls":
		sim.troll.on_damaged(target)
	sim.events.emit_event("unit_damaged", {"unit_id": target.id, "amount": effective, "hp": target.hp})
	if target.hp <= 0:
		var was_elf := target.kind == UnitState.KIND_ELF
		sim.unit_svc.kill_unit(target)
		if was_elf and attacker and attacker.team == "trolls":
			sim.troll.add_xp(int(sim.cfg["troll"]["xp_per_elf_kill"]), "elf_kill")
	return effective


# ---------- 塔 ----------

func tick_towers() -> void:
	var ids := sim.buildings.keys()
	ids.sort()
	for iid in ids:
		var inst: BuildingInstance = sim.buildings.get(iid)
		if inst == null or not inst.is_functional():
			continue
		var lv: Dictionary = sim.defs.get_def(inst.def_id).level(inst.level)
		var atk: Dictionary = lv.get("attack", {})
		if not atk.is_empty():
			if inst.attack_cooldown > 0:
				inst.attack_cooldown -= 1
			if inst.attack_cooldown <= 0:
				var t := pick_tower_target(inst, float(atk["range"]))
				if t:
					damage_unit(null, t, int(atk["damage"]))
					inst.attack_cooldown = int(atk["interval_ticks"])
					sim.events.emit_event("tower_fired", {"instance_id": iid, "target_unit_id": t.id})
		var slow: Dictionary = lv.get("slow", {})
		if not slow.is_empty():
			if inst.slow_cooldown > 0:
				inst.slow_cooldown -= 1
			if inst.slow_cooldown <= 0:
				var t2 := pick_tower_target(inst, float(slow["range"]))
				if t2:
					# 以來源塔為鍵記錄；移動時只取最強一項，不疊加
					t2.slows[iid] = {"percent": int(slow["percent"]), "until_tick": sim.tick + int(slow["duration_ticks"])}
					inst.slow_cooldown = int(slow["interval_ticks"])
					sim.events.emit_event("tower_slowed", {"instance_id": iid, "target_unit_id": t2.id, "percent": slow["percent"]})


## 選敵：存活、已出場、敵方、精靈方可見、在射程內。
## 優先序：正在攻擊友方建築 > 距離最近 > 單位 ID 小。
func pick_tower_target(inst: BuildingInstance, rng: float) -> UnitState:
	var best: UnitState = null
	var best_key := []
	var c := inst.center()
	for u in sim.units.values():
		var unit: UnitState = u
		if not unit.on_map() or unit.team != "trolls":
			continue
		if not sim.visibility.is_visible_to("elves", unit.pos):
			continue
		var dist := c.distance_to(unit.pos)
		if dist > rng:
			continue
		var attacking := 0 if (sim.tick - unit.last_building_attack_tick) <= sim.tick_rate else 1
		var key := [attacking, dist, unit.id]
		if best == null or _key_less(key, best_key):
			best = unit
			best_key = key
	return best


static func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] < b[i]:
			return true
		if a[i] > b[i]:
			return false
	return false
