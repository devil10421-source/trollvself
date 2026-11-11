class_name SoulService
extends RefCounted
## V0.7 精靈靈魂：三個技能（修復之光／星光印記／藤蔓纏繞）一開始都是 Lv1，
## 每存在 90 秒得 1 點，可把任一技能升到最高 Lv3；無職業分支。
## 修復之光走 RepairService（免費、耗靈魂能量）。

const SKILLS := ["repair", "mark", "root"]

var sim: MatchSim


func _init(s: MatchSim) -> void:
	sim = s


func scfg() -> Dictionary:
	return sim.cfg["soul"]


func soul_of(pid: int) -> UnitState:
	var u: UnitState = sim.unit_of(pid)
	if u == null or not u.alive or u.kind != UnitState.KIND_SOUL:
		return null
	return u


func tick() -> void:
	var every := sim.defs.sec_to_ticks(float(scfg()["point_every_sec"]))
	for v in sim.units.values():
		var u: UnitState = v
		if u.kind != UnitState.KIND_SOUL or not u.alive:
			continue
		u.soul_point_tick += 1
		if u.soul_point_tick >= every:
			u.soul_point_tick = 0
			u.soul_points += 1
			sim.events.emit_event("soul_point", {"player_id": u.player_id, "points": u.soul_points})


func upgrade(pid: int, skill: String) -> Dictionary:
	var u := soul_of(pid)
	if u == null:
		return {"ok": false, "reason": "not_a_soul"}
	if not SKILLS.has(skill):
		return {"ok": false, "reason": "unknown_skill"}
	if u.soul_points <= 0:
		return {"ok": false, "reason": "no_soul_points"}
	var lv := int(u.soul_skills.get(skill, 1))
	if lv >= int(scfg()["max_skill_level"]):
		return {"ok": false, "reason": "max_level"}
	u.soul_points -= 1
	u.soul_skills[skill] = lv + 1
	sim.events.emit_event("soul_skill_up", {"player_id": pid, "skill": skill, "level": lv + 1})
	return {"ok": true}


func cooldown_left_sec(u: UnitState, skill: String) -> float:
	return maxf(0.0, float(int(u.skill_ready.get(skill, 0)) - sim.tick) / sim.tick_rate)


## 範圍內最近、可見、已出場的巨魔方單位。
func nearest_target(u: UnitState, rng: float) -> UnitState:
	var best: UnitState = null
	var bd := rng + 0.0001
	var ids := sim.units.keys()
	ids.sort()
	for tid in ids:
		var t: UnitState = sim.units[tid]
		if t.team != "trolls" or not t.on_map() or not sim.visibility.is_visible_to("elves", t.pos):
			continue
		var d := u.pos.distance_to(t.pos)
		if d < bd:
			bd = d
			best = t
	return best


## mark / root。target_id 省略 = 自動選範圍內最近的巨魔方單位。
func cast(pid: int, skill: String, target_id: int = -1) -> Dictionary:
	if sim.is_over():
		return {"ok": false, "reason": "match_over"}
	var u := soul_of(pid)
	if u == null:
		return {"ok": false, "reason": "not_a_soul"}
	if skill != "mark" and skill != "root":
		return {"ok": false, "reason": "unknown_skill"}
	var sk: Dictionary = scfg()["skills"][skill]
	if sim.tick < int(u.skill_ready.get(skill, 0)):
		return {"ok": false, "reason": "cooldown", "detail": "%.1f 秒" % cooldown_left_sec(u, skill)}
	var rng := float(sk["range"])
	var t: UnitState = sim.units.get(target_id) if target_id != -1 else nearest_target(u, rng)
	if t == null or t.team != "trolls" or not t.on_map() or u.pos.distance_to(t.pos) > rng:
		return {"ok": false, "reason": "no_target_in_range"}
	var lv := int(u.soul_skills.get(skill, 1))
	if skill == "mark":
		t.marked_until = sim.tick + sim.defs.sec_to_ticks(float(sk["duration_sec"]))
		t.marked_bonus = int(sk["bonus_percent"][lv - 1])
	else:
		if sim.tick < t.root_immune_until:
			return {"ok": false, "reason": "target_root_immune"}
		var dur := sim.defs.sec_to_ticks(float(sk["duration_sec"][lv - 1]))
		t.rooted_until = sim.tick + dur
		t.root_immune_until = t.rooted_until + sim.defs.sec_to_ticks(float(sk["immunity_sec"]))
		t.path = []
	u.skill_ready[skill] = sim.tick + sim.defs.sec_to_ticks(float(sk["cooldown_sec"]))
	sim.events.emit_event("soul_skill", {"player_id": pid, "skill": skill, "target_unit_id": t.id, "level": lv})
	return {"ok": true, "target_unit_id": t.id}
