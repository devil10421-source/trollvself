class_name ElfBot
extends RefCounted
## 試玩版用的電腦精靈（不是正式 AI）。只透過 sim.submit() 下指令，和玩家用同一套規則。
## 行為：照固定順序蓋建築 → 沒事就進樹屋賺錢 → 巨魔靠近就躲回屋裡關門 → 門或牆受損就按修復鈕。
## 陣亡後變成靈魂：跟著巨魔放星光印記、藤蔓纏繞，並修受損的門。

const THREAT_RADIUS := 12.0

## 建造順序。build = 這種建築蓋到 n 座；up = 這種建築全部升到 lv。
const PLAN := [
	{"k": "build", "def": "elf_house", "n": 1},
	{"k": "build", "def": "lumber_grove", "n": 1},
	{"k": "up", "def": "elf_house", "lv": 2},
	{"k": "build", "def": "craft_hall", "n": 1},
	{"k": "build", "def": "arrow_tower", "n": 2},
	{"k": "up", "def": "lumber_grove", "lv": 2},
	{"k": "up", "def": "elf_house", "lv": 3},
	{"k": "build", "def": "arrow_tower", "n": 3},
	{"k": "up", "def": "craft_hall", "lv": 2},
	{"k": "up", "def": "lumber_grove", "lv": 3},
	{"k": "build", "def": "arrow_tower", "n": 4},
	{"k": "up", "def": "arrow_tower", "lv": 2},
	{"k": "up", "def": "elf_house", "lv": 4},
	{"k": "build", "def": "frost_tower", "n": 1},
	{"k": "build", "def": "arrow_tower", "n": 6},
	{"k": "up", "def": "craft_hall", "lv": 3},
	{"k": "up", "def": "arrow_tower", "lv": 3},
	{"k": "build", "def": "frost_tower", "n": 2},
	{"k": "up", "def": "frost_tower", "lv": 2},
]

var sim: MatchSim
var pids: Array = []


func _init(s: MatchSim, bot_pids: Array) -> void:
	sim = s
	pids = bot_pids


## 每個 sim.step() 之後呼叫一次；每位電腦精靈每秒思考一次（錯開）。
func tick() -> void:
	if sim.is_over():
		return
	for pid in pids:
		if (sim.tick + int(pid) * 3) % sim.tick_rate == 0:
			_think(pid)


func _think(pid: int) -> void:
	var p: PlayerAccount = sim.players.get(pid)
	if p == null:
		return
	if p.afterlife == "pending":
		sim.submit({"type": "death_choice", "player_id": pid, "choice": "soul"})
		return
	if p.afterlife == "soul":
		_think_soul(pid)
		return
	if not p.alive_original:
		return
	var u: UnitState = sim.unit_of(pid)
	if u == null or not u.alive:
		return
	# 門或牆受損就按修復（免費）
	if sim.house.repair_target(pid) != null and sim.house.repair_cooldown_left_sec(pid) <= 0.0:
		sim.submit({"type": "house_repair", "player_id": pid})
	var house: BuildingInstance = sim.house.house_of(pid)
	var has_house := house != null and house.is_functional()
	# 有樹屋就待在屋裡（門關著、金幣加成），蓋東西用遠端施工
	if has_house and u.inside_house == -1:
		if u.order.get("type") != "enter_house":
			sim.submit({"type": "enter_house", "player_id": pid})
		return
	# 手上有工作就繼續；被打斷的工地接回來
	var job: BuildingInstance = sim.buildings.get(p.job_instance_id)
	if job != null and job.has_job():
		return
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if inst.owner_player_id == pid and inst.has_job() and inst.def_id != "escape_portal":
			sim.submit({"type": "resume_build", "player_id": pid, "instance_id": inst.instance_id})
			return
	_advance_plan(pid)


func _threatened(pid: int) -> bool:
	var g: BuildingInstance = sim.house.gate_of(pid)
	var house: BuildingInstance = sim.house.house_of(pid)
	var anchor := GridMath.cell_center(sim.grid.elf_spawns.get(pid, Vector2i.ZERO))
	if g:
		anchor = g.center()
	for v in sim.units.values():
		var t: UnitState = v
		if t.team != "trolls" or not t.on_map():
			continue
		if t.pos.distance_to(anchor) <= THREAT_RADIUS:
			return true
		if house and t.pos.distance_to(house.center()) <= THREAT_RADIUS:
			return true
	return false


## 回傳 true = 這次思考已經下了建造／升級指令。
func _advance_plan(pid: int) -> bool:
	for step in PLAN:
		var def_id: String = step["def"]
		if step["k"] == "build":
			if sim.building_svc.count_owned(pid, def_id) >= int(step["n"]):
				continue
			var d: BuildingDefinition = sim.defs.get_def(def_id)
			var lv1 := d.level(1)
			if sim.building_svc.missing_requirement(pid, lv1["requires"]) != "":
				continue  # 前置還沒到，先做後面做得到的
			if not sim.economy.can_afford(pid, lv1["cost_g"], lv1["cost_w"]):
				return false  # 存錢
			for origin in _slots(pid, def_id):
				if sim.building_svc.validate_place(pid, def_id, origin)["ok"]:
					return sim.submit({"type": "build", "player_id": pid, "def_id": def_id, "origin": origin})["ok"]
			continue
		else:
			var target: BuildingInstance = null
			for b in sim.buildings.values():
				var inst: BuildingInstance = b
				if inst.owner_player_id == pid and inst.def_id == def_id and inst.is_alive() \
						and inst.state == BuildingInstance.ST_ACTIVE and inst.level < int(step["lv"]):
					if target == null or inst.instance_id < target.instance_id:
						target = inst
			if target == null:
				continue
			var v := sim.building_svc.validate_upgrade(pid, target.instance_id)
			if v["ok"]:
				return sim.submit({"type": "upgrade", "player_id": pid, "instance_id": target.instance_id})["ok"]
			if v["reason"] == "insufficient_resources":
				return false
			continue
	return false


## 依出生點與樹樁門的相對位置，算出這個基地各種建築的候選位置。
func _slots(pid: int, def_id: String) -> Array:
	var s: Vector2i = sim.grid.elf_spawns.get(pid, Vector2i.ZERO)
	var g: BuildingInstance = sim.house.gate_of(pid)
	var gx := s.x
	var gy := s.y + 5
	if g:
		gx = g.origin.x
		gy = g.origin.y
	var dir := 1 if gy > s.y else -1          # 門在出生點的哪一側（+1 = 下方）
	var far_y := s.y - 2 if dir > 0 else s.y + 2   # 遠離門的那一排
	var near_y := s.y + 1 if dir > 0 else s.y - 2  # 靠門的那一排
	var ty := gy - dir * 2                    # 塔排
	var out: Array = []
	match def_id:
		"elf_house":
			out = [Vector2i(s.x - 4, far_y), Vector2i(s.x - 2, far_y), Vector2i(s.x + 1, far_y)]
		"lumber_grove":
			out = [Vector2i(s.x + 3, far_y), Vector2i(s.x + 1, far_y), Vector2i(s.x - 2, far_y)]
		"craft_hall":
			out = [Vector2i(s.x - 4, near_y), Vector2i(s.x + 3, near_y), Vector2i(s.x - 2, near_y)]
		"arrow_tower":
			for row in [ty, ty - dir]:
				for dx in [-1, 2, -3, 4, -5, 6]:
					out.append(Vector2i(gx + dx, row))
		"frost_tower":
			for row in [ty - dir, ty - dir * 2]:
				for dx in [-2, 3, -4, 5]:
					out.append(Vector2i(gx + dx, row))
		_:
			for dx in [-1, 2, -3, 4]:
				out.append(Vector2i(gx + dx, ty - dir * 2))
	return out


# ---------- 靈魂 ----------

func _think_soul(pid: int) -> void:
	var u: UnitState = sim.unit_of(pid)
	if u == null or not u.alive:
		return
	# 有技能點就升級（輪流）
	if u.soul_points > 0:
		for sk in ["root", "mark", "repair"]:
			if sim.submit({"type": "soul_upgrade", "player_id": pid, "skill": sk})["ok"]:
				break
	var troll := _nearest_troll(u.pos)
	if troll and u.pos.distance_to(troll.pos) <= 6.0:
		sim.submit({"type": "soul_skill", "player_id": pid, "skill": "mark"})
		sim.submit({"type": "soul_skill", "player_id": pid, "skill": "root"})
	# 修最殘的友方門／牆／樹屋；沒得修就跟著巨魔
	if u.order.get("type") == "repair":
		return
	var worst: BuildingInstance = null
	var worst_ratio := 0.95
	for b in sim.buildings.values():
		var inst: BuildingInstance = b
		if inst.team_id != "elves" or not sim.repair.can_unit_repair(u, inst):
			continue
		var owner: PlayerAccount = sim.players.get(inst.owner_player_id)
		if owner == null or not owner.alive_original:
			continue
		var ratio := float(inst.hp) / maxf(1.0, inst.max_hp)
		if ratio < worst_ratio:
			worst_ratio = ratio
			worst = inst
	if worst:
		sim.submit({"type": "repair", "player_id": pid, "instance_id": worst.instance_id})
	elif troll and u.pos.distance_to(troll.pos) > 4.0:
		sim.submit({"type": "move", "player_id": pid, "cell": [troll.cell().x, troll.cell().y]})


func _nearest_troll(p: Vector2) -> UnitState:
	var best: UnitState = null
	var bd := 1e9
	for v in sim.units.values():
		var t: UnitState = v
		if t.team == "trolls" and t.on_map():
			var d := p.distance_to(t.pos)
			if d < bd:
				bd = d
				best = t
	return best
