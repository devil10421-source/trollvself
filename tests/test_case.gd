extends RefCounted
## 測試基底：每個 test_ 開頭的方法就是一項測試。

var failures: Array[String] = []
var current := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s：%s" % [current, msg])


func eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s：%s（實際 %s，預期 %s）" % [current, msg, str(actual), str(expected)])


# ---------- 共用工具 ----------

## 建立一局：預設巨魔不出場、AI 關閉，避免干擾。overrides 會覆蓋 match_config。
func new_sim(overrides: Dictionary = {}, elf_count: int = 3) -> MatchSim:
	var base := {"troll": {"spawn_delay_sec": 99999}}
	DefinitionDB.deep_merge(base, overrides)
	var defs := DefinitionDB.load_default(base)
	assert(defs.is_valid(), str(defs.errors))
	var sim := MatchSim.create(defs, elf_count)
	troll(sim).ai_enabled = false
	return sim


func troll(sim: MatchSim) -> UnitState:
	return sim.unit_of(MatchSim.TROLL_PLAYER_ID)


func spawn_troll(sim: MatchSim, cell: Vector2i) -> UnitState:
	var u := troll(sim)
	u.spawned = true
	u.ai_enabled = false
	teleport(u, cell)
	return u


func teleport(u: UnitState, c: Vector2i) -> void:
	u.pos = GridMath.cell_center(c)
	u.path = []


func set_res(sim: MatchSim, pid: int, g: int, w: int) -> void:
	sim.players[pid].gold = g
	sim.players[pid].wood = w


## 直接放一座「已完成」建築（測試捷徑，不經過扣款），累計成本照表計入。
func add_building(sim: MatchSim, pid: int, def_id: String, origin: Vector2i, level: int) -> BuildingInstance:
	var d := sim.defs.get_def(def_id)
	var inst := BuildingInstance.new()
	inst.instance_id = sim.next_id()
	inst.def_id = def_id
	inst.owner_player_id = pid
	inst.origin = origin
	inst.size = d.footprint
	inst.level = level
	inst.state = BuildingInstance.ST_ACTIVE
	inst.max_hp = d.level(level)["hp"]
	inst.hp = inst.max_hp
	for i in range(1, level + 1):
		inst.total_paid_g += d.level(i)["cost_g"]
		inst.total_paid_w += d.level(i)["cost_w"]
	sim.buildings[inst.instance_id] = inst
	sim.grid.occupy(origin, d.footprint, inst.instance_id)
	if def_id == "elf_house":
		sim.house.refresh_gate_hp(pid)
	return inst


## 一直推進直到條件成立或超時（秒）。
func run_until(sim: MatchSim, cond: Callable, max_sec: float) -> bool:
	for i in int(max_sec * sim.tick_rate):
		if cond.call():
			return true
		sim.step()
	return cond.call()


## 封住正式測試地圖的保護區入口（38,15）（38,16）。
func seal_portal_zone(sim: MatchSim, pid: int) -> void:
	add_building(sim, pid, "wall", Vector2i(38, 15), 1)
	add_building(sim, pid, "wall", Vector2i(38, 16), 1)


## 讓 pid 符合傳送門前置並站到保護區內。
func ready_for_portal(sim: MatchSim, pid: int, house_origin: Vector2i, hall_origin: Vector2i) -> void:
	add_building(sim, pid, "elf_house", house_origin, 4)
	add_building(sim, pid, "craft_hall", hall_origin, 2)
	set_res(sim, pid, 20000, 5000)
	sim.tick = sim.escape.unlock_tick()


## 玩家蓋的建築（不含地圖自動生成的樹樁門）。
func player_buildings(sim: MatchSim) -> Array:
	var out := []
	for b in sim.buildings.values():
		if (b as BuildingInstance).def_id != "stump_gate":
			out.append(b)
	return out


## 讓精靈 pid 有一座完成的樹屋並直接入屋。
func put_inside(sim: MatchSim, pid: int, house: BuildingInstance) -> void:
	sim.house.do_enter(sim.unit_of(pid), house)
