class_name EconomyService
extends RefCounted
## 金幣 / 木材帳戶。所有扣款都是「先檢查兩種資源、再一起扣」的原子操作，不允許負債。

var sim: MatchSim


func _init(s: MatchSim) -> void:
	sim = s


func can_afford(pid: int, g: int, w: int) -> bool:
	var p: PlayerAccount = sim.players.get(pid)
	return p != null and g >= 0 and w >= 0 and p.gold >= g and p.wood >= w


func spend(pid: int, g: int, w: int, reason: String) -> bool:
	if not can_afford(pid, g, w):
		return false
	var p: PlayerAccount = sim.players[pid]
	p.gold -= g
	p.wood -= w
	if g != 0 or w != 0:
		sim.events.emit_event("economy_changed", {"player_id": pid, "gold": p.gold, "wood": p.wood, "delta_g": -g, "delta_w": -w, "reason": reason})
	return true


func grant(pid: int, g: int, w: int, reason: String) -> void:
	var p: PlayerAccount = sim.players.get(pid)
	if p == null or (g == 0 and w == 0):
		return
	p.gold += g
	p.wood += w
	sim.events.emit_event("economy_changed", {"player_id": pid, "gold": p.gold, "wood": p.wood, "delta_g": g, "delta_w": w, "reason": reason})


## 存活精靈之間無手續費贈送。
func donate(from_id: int, to_id: int, g: int, w: int) -> Dictionary:
	var a: PlayerAccount = sim.players.get(from_id)
	var b: PlayerAccount = sim.players.get(to_id)
	if a == null or b == null or from_id == to_id:
		return {"ok": false, "reason": "invalid_player"}
	if not a.alive_original or not b.alive_original:
		return {"ok": false, "reason": "both_must_be_living_elves"}
	if g < 0 or w < 0 or (g == 0 and w == 0):
		return {"ok": false, "reason": "invalid_amount"}
	if not spend(from_id, g, w, "donate_out"):
		return {"ok": false, "reason": "insufficient_resources"}
	grant(to_id, g, w, "donate_in")
	return {"ok": true}


## 每秒結算一次：已完成（含升級中，依舊等級）的樹屋 / 林場，且擁有者仍是存活原始精靈。
func produce_per_second() -> void:
	var gains := {}
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if not inst.is_functional():
			continue
		var owner: PlayerAccount = sim.players.get(inst.owner_player_id)
		if owner == null or not owner.alive_original:
			continue
		var lv: Dictionary = sim.defs.get_def(inst.def_id).level(inst.level)
		var g := int(lv.get("gold_per_sec", 0))
		if inst.def_id == "elf_house":
			g = sim.house.gold_with_bonus(inst.owner_player_id, inst, g)
		var w := int(lv.get("wood_per_sec", 0))
		if g == 0 and w == 0:
			continue
		var cur: Array = gains.get(inst.owner_player_id, [0, 0])
		gains[inst.owner_player_id] = [cur[0] + g, cur[1] + w]
	var ids := gains.keys()
	ids.sort()
	for pid in ids:
		grant(pid, gains[pid][0], gains[pid][1], "production")
