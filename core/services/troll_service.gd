class_name TrollService
extends RefCounted
## V0.7 巨魔方：經驗與等級、巢穴回血、四個技能、僕從跟隨主巨魔等級。
## 循環：出巢 → 拆牆拿經驗 → 被塔打到殘血 → 回巢補血 → 更強再來。

const SKILLS := ["recall", "smash", "roar", "rampage"]

var sim: MatchSim


func _init(s: MatchSim) -> void:
	sim = s


func tcfg() -> Dictionary:
	return sim.cfg["troll"]


func levels() -> Array:
	return tcfg()["levels"]


func max_level() -> int:
	return levels().size()


func main_troll() -> UnitState:
	return sim.unit_of(MatchSim.TROLL_PLAYER_ID)


# ---------- 數值 ----------

## 依等級套用數值。HP 提升時當下血量一起加上差額。
func apply_stats(u: UnitState) -> void:
	var lv := clampi(u.level, 1, max_level())
	var row: Dictionary = levels()[lv - 1]
	var new_max := int(row["hp"])
	var dmg := int(row["damage"])
	if u.kind == UnitState.KIND_MINION:
		var pct := int(sim.cfg["minion"]["stat_percent"])
		new_max = new_max * pct / 100
		dmg = dmg * pct / 100
	var diff := new_max - u.max_hp
	u.max_hp = new_max
	u.hp = clampi(u.hp + maxi(0, diff), 1, new_max) if u.alive else new_max
	u.damage = dmg


func minion_level() -> int:
	var t := main_troll()
	var base := t.level if t else 1
	return maxi(1, base + int(sim.cfg["minion"]["level_offset"]))


## 經驗：主巨魔與僕從的有效建築傷害都算進主巨魔。
func add_xp(amount: int, reason: String) -> void:
	var t := main_troll()
	if t == null or amount <= 0:
		return
	t.xp += amount
	while t.level < max_level():
		var need := int(levels()[t.level - 1]["xp"])
		if t.xp < need:
			break
		t.xp -= need
		t.level += 1
		apply_stats(t)
		sim.events.emit_event("troll_level_up", {"unit_id": t.id, "level": t.level})
		_sync_minions()
	if t.level >= max_level():
		t.xp = 0
	sim.events.emit_event("troll_xp", {"amount": amount, "reason": reason, "xp": t.xp, "level": t.level})


func _sync_minions() -> void:
	var lv := minion_level()
	for v in sim.units.values():
		var u: UnitState = v
		if u.kind == UnitState.KIND_MINION and u.level != lv:
			u.level = lv
			apply_stats(u)


func xp_to_next(u: UnitState) -> int:
	if u.level >= max_level():
		return 0
	return int(levels()[u.level - 1]["xp"])


func respawn_ticks(u: UnitState) -> int:
	var sec := float(tcfg()["respawn_base_sec"]) + float(tcfg()["respawn_per_level_sec"]) * u.level
	return sim.defs.sec_to_ticks(sec)


func in_nest(u: UnitState) -> bool:
	return sim.grid.troll_spawn_cells.has(u.cell())


func nest_cell() -> Vector2i:
	return sim.grid.troll_spawn_cells[0]


# ---------- 每 tick ----------

func tick() -> void:
	var ids := sim.units.keys()
	ids.sort()
	for uid in ids:
		var u: UnitState = sim.units[uid]
		if u.team != "trolls" or not u.alive or not u.spawned:
			continue
		_regen(u)
		if u.channel_kind == "recall" and sim.tick >= u.channel_until:
			u.channel_kind = ""
			u.channel_until = -1
			u.pos = GridMath.cell_center(nest_cell())
			u.path = []
			sim.unit_svc.set_order(u, {"type": "idle"})
			u.skill_ready["recall"] = sim.tick + sim.defs.sec_to_ticks(float(tcfg()["skills"]["recall"]["cooldown_sec"]))
			sim.events.emit_event("troll_recalled", {"unit_id": u.id})


func _regen(u: UnitState) -> void:
	if u.hp >= u.max_hp:
		u.regen_carry = 0.0
		return
	var pct := 0.0
	if in_nest(u):
		pct = float(tcfg()["nest_regen_percent_per_sec"])
	elif sim.tick - u.last_damaged_tick >= sim.defs.sec_to_ticks(float(tcfg()["field_regen_delay_sec"])):
		pct = float(tcfg()["field_regen_percent_per_sec"])
	if pct <= 0.0:
		return
	u.regen_carry += u.max_hp * pct / 100.0 / sim.tick_rate
	var whole := int(floor(u.regen_carry))
	if whole > 0:
		u.regen_carry -= whole
		u.hp = mini(u.max_hp, u.hp + whole)


## 受傷時：記錄時間、打斷回巢引導。由 CombatService 呼叫。
func on_damaged(u: UnitState) -> void:
	u.last_damaged_tick = sim.tick
	if u.channel_kind == "recall":
		u.channel_kind = ""
		u.channel_until = -1
		sim.events.emit_event("troll_recall_interrupted", {"unit_id": u.id})


## 受到的傷害倍率（狂暴 +20%）。
func damage_taken_mult_percent(u: UnitState) -> int:
	if sim.tick < u.rampage_until:
		return 100 + int(tcfg()["skills"]["rampage"]["damage_taken_percent"])
	return 100


## 攻擊間隔（狂暴攻速 +50% → 間隔 ÷ 1.5）。
func attack_interval(u: UnitState) -> int:
	if sim.tick < u.rampage_until:
		var pct := int(tcfg()["skills"]["rampage"]["attack_speed_percent"])
		return maxi(1, u.attack_interval_ticks * 100 / (100 + pct))
	return u.attack_interval_ticks


# ---------- 技能 ----------

func skill_list(u: UnitState) -> Array:
	if u.kind == UnitState.KIND_MINION:
		return sim.cfg["minion"]["skills"]
	return SKILLS


func unlock_level(skill: String) -> int:
	return int(tcfg()["skills"][skill]["unlock_level"])


func cooldown_left_sec(u: UnitState, skill: String) -> float:
	return maxf(0.0, float(int(u.skill_ready.get(skill, 0)) - sim.tick) / sim.tick_rate)


func can_cast(u: UnitState, skill: String) -> String:
	if u == null or not u.alive or not u.spawned or u.team != "trolls":
		return "not_a_troll_unit"
	if not skill_list(u).has(skill):
		return "unknown_skill"
	var need := unlock_level(skill)
	var lv := u.level
	if lv < need:
		return "skill_locked"
	if skill == "recall" and in_nest(u):
		return "already_in_nest"
	if sim.tick < int(u.skill_ready.get(skill, 0)):
		return "cooldown"
	if u.channel_kind != "":
		return "channeling"
	if sim.tick < u.stunned_until:
		return "stunned"
	return ""


func cast(u: UnitState, skill: String) -> Dictionary:
	var why := can_cast(u, skill)
	if why != "":
		var r := {"ok": false, "reason": why}
		if why == "skill_locked":
			r["detail"] = "Lv%d 解鎖" % unlock_level(skill)
		elif why == "cooldown":
			r["detail"] = "%.1f 秒" % cooldown_left_sec(u, skill)
		return r
	var sk: Dictionary = tcfg()["skills"][skill]
	match skill:
		"recall":
			u.channel_kind = "recall"
			u.channel_until = sim.tick + sim.defs.sec_to_ticks(float(sk["channel_sec"]))
			u.path = []
			# 冷卻在成功回到巢穴時才開始
		"smash":
			u.smash_ready = true
			_start_cd(u, skill)
		"roar":
			_roar(u, sk)
			_start_cd(u, skill)
		"rampage":
			u.rampage_until = sim.tick + sim.defs.sec_to_ticks(float(sk["duration_sec"]))
			_start_cd(u, skill)
	sim.events.emit_event("troll_skill", {"unit_id": u.id, "skill": skill})
	return {"ok": true}


func _start_cd(u: UnitState, skill: String) -> void:
	u.skill_ready[skill] = sim.tick + sim.defs.sec_to_ticks(float(tcfg()["skills"][skill]["cooldown_sec"]))


## 威嚇怒吼：半徑內精靈的普通施工暫停；半徑內建築的修復暫停，之後一段時間修復量下降。不影響傳送門。
func _roar(u: UnitState, sk: Dictionary) -> void:
	var r := float(sk["radius"])
	var pause := sim.defs.sec_to_ticks(float(sk["pause_sec"]))
	var slow := sim.defs.sec_to_ticks(float(sk["repair_slow_sec"]))
	for v in sim.units.values():
		var e: UnitState = v
		if e.team == "elves" and e.alive and e.pos.distance_to(u.pos) <= r:  # 屋內精靈以樹屋位置計
			e.build_block_until = sim.tick + pause
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if inst.team_id != "elves" or sim.defs.get_def(inst.def_id).is_portal():
			continue
		if GridMath.point_to_rect(u.pos, inst.origin, inst.size) <= r:
			inst.repair_block_until = sim.tick + pause
			inst.repair_slow_until = sim.tick + pause + slow
			inst.repair_slow_percent = int(sk["repair_slow_percent"])


## 重擊：下一下打建築時倍率。由 UnitService 出手時呼叫，回傳實際傷害。
func consume_smash(u: UnitState, base: int, is_building: bool) -> int:
	if is_building and u.smash_ready:
		u.smash_ready = false
		return base * int(tcfg()["skills"]["smash"]["multiplier"])
	return base


# ---------- 測試用 AI 的技能判斷 ----------

## 回傳 true 表示 AI 這次思考已處理（撤退中）。
func ai_tactics(u: UnitState) -> bool:
	var hp_pct := 100 * u.hp / maxi(1, u.max_hp)
	if u.ai_mode == "retreat":
		if in_nest(u) and hp_pct >= int(tcfg()["ai_return_hp_percent"]):
			u.ai_mode = ""
			return false
		if in_nest(u):
			if u.order.get("type") != "idle":
				sim.unit_svc.set_order(u, {"type": "idle"})
			return true
		if u.channel_kind == "":
			# 還在挨打時引導會被打斷：先走出射程，脫戰 2 秒後再回巢
			var safe := sim.tick - u.last_damaged_tick > 2 * sim.tick_rate
			if safe and can_cast(u, "recall") == "":
				cast(u, "recall")
			elif u.order.get("type") != "move":
				sim.unit_svc.set_order(u, {"type": "move", "cell": nest_cell()})
		return true
	if hp_pct < int(tcfg()["ai_retreat_hp_percent"]) and not in_nest(u):
		u.ai_mode = "retreat"
		return ai_tactics(u)
	if u.order.get("type") == "attack" and u.order.get("target_kind") == "building":
		if can_cast(u, "smash") == "":
			cast(u, "smash")
		var inst: BuildingInstance = sim.buildings.get(u.order.get("target_id"))
		if inst and GridMath.point_to_rect(u.pos, inst.origin, inst.size) <= 2.5:
			if can_cast(u, "rampage") == "":
				cast(u, "rampage")
			if can_cast(u, "roar") == "":
				cast(u, "roar")
	return false
