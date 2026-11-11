class_name MatchSim
extends RefCounted
## 單局權威模擬。畫面 / 測試 / 未來的伺服器都只透過 submit() 送指令、step() 推進時間。
## 指令依到達順序逐一處理（等同單一佇列），所以同 tick 的衝突永遠是先到先贏。
## 帶 request_id 的指令重送時，直接回傳第一次的結果，不會重複建造或扣款。

const TROLL_PLAYER_ID := 100

var defs: DefinitionDB
var cfg: Dictionary
var grid: TileGrid
var events := EventBus.new()
var tick := 0
var tick_rate := 10
var players := {}     # id -> PlayerAccount
var units := {}       # id -> UnitState
var buildings := {}   # instance_id -> BuildingInstance

var economy: EconomyService
var building_svc: BuildingService
var combat: CombatService
var repair: RepairService
var visibility: VisibilityService
var escape: EscapeService
var match_svc: MatchService
var unit_svc: UnitService
var house: HouseService
var troll: TrollService
var soul: SoulService

var _next_id := 1
var _processed := {}  # request_id -> result
var troll_spawn_tick := 0


## 建立一局。elf_count 名原始精靈 + 1 名主巨魔。map_text 為空時讀設定檔的地圖。
static func create(p_defs: DefinitionDB, elf_count: int = 3, map_text: String = "") -> MatchSim:
	var s := MatchSim.new()
	s._setup(p_defs, elf_count, map_text)
	return s


func _setup(p_defs: DefinitionDB, elf_count: int, map_text: String) -> void:
	defs = p_defs
	cfg = defs.config
	tick_rate = defs.tick_rate()
	grid = TileGrid.new()
	if map_text == "":
		map_text = FileAccess.get_file_as_string(str(cfg["map"]))
	var err := grid.load_from_text(map_text)
	assert(err == "", err)
	economy = EconomyService.new(self)
	building_svc = BuildingService.new(self)
	combat = CombatService.new(self)
	repair = RepairService.new(self)
	visibility = VisibilityService.new(self)
	escape = EscapeService.new(self)
	match_svc = MatchService.new(self)
	unit_svc = UnitService.new(self)
	house = HouseService.new(self)
	troll = TrollService.new(self)
	soul = SoulService.new(self)
	for i in range(1, elf_count + 1):
		var p := PlayerAccount.new()
		p.id = i
		p.display_name = "精靈 %d" % i
		p.role = "elf"
		p.gold = int(cfg["start_gold"])
		p.wood = int(cfg["start_wood"])
		p.alive_original = true
		players[i] = p
		var cell: Vector2i = grid.elf_spawns.get(i, grid.elf_spawns.values()[0])
		p.unit_id = unit_svc.spawn_unit(UnitState.KIND_ELF, i, cell).id
	var t := PlayerAccount.new()
	t.id = TROLL_PLAYER_ID
	t.display_name = "巨魔"
	t.role = "troll"
	players[t.id] = t
	var tu := unit_svc.spawn_unit(UnitState.KIND_TROLL, t.id, grid.troll_spawn_cells[0])
	troll_spawn_tick = defs.sec_to_ticks(float(cfg["troll"].get("spawn_delay_sec", 0)))
	tu.spawned = troll_spawn_tick <= 0
	tu.ai_enabled = true
	t.unit_id = tu.id
	house.create_gates()
	visibility.recompute()


func next_id() -> int:
	_next_id += 1
	return _next_id


func now_sec() -> float:
	return float(tick) / tick_rate


func is_over() -> bool:
	return match_svc.is_locked()


func result() -> Dictionary:
	return match_svc.result


# ---------- 指令 ----------

## cmd 範例：{"type":"build","player_id":1,"def_id":"wall","origin":[10,10],"request_id":"abc"}
func submit(cmd: Dictionary) -> Dictionary:
	var rid = cmd.get("request_id", null)
	if rid != null and _processed.has(rid):
		var prev: Dictionary = _processed[rid].duplicate()
		prev["duplicate"] = true
		return prev
	var res := _dispatch(cmd)
	if rid != null:
		_processed[rid] = res
	return res


func _dispatch(cmd: Dictionary) -> Dictionary:
	var pid := int(cmd.get("player_id", -1))
	var t := str(cmd.get("type", ""))
	if is_over() and not t.begins_with("debug_"):
		return {"ok": false, "reason": "match_over"}
	match t:
		"build":
			return building_svc.place(pid, str(cmd["def_id"]), _v2i(cmd["origin"]))
		"upgrade":
			return building_svc.upgrade(pid, int(cmd["instance_id"]))
		"cancel":
			return building_svc.cancel(pid, int(cmd["instance_id"]))
		"demolish":
			return building_svc.demolish(pid, int(cmd["instance_id"]))
		"resume_build":
			return building_svc.assign_job(pid, int(cmd["instance_id"]))
		"repair":
			return repair.start_repair(pid, int(cmd["instance_id"]))
		"donate":
			return economy.donate(pid, int(cmd["to_player_id"]), int(cmd.get("gold", 0)), int(cmd.get("wood", 0)))
		"move":
			return unit_svc.command_move(pid, _v2i(cmd["cell"]))
		"attack":
			return unit_svc.command_attack(pid, str(cmd["target_kind"]), int(cmd["target_id"]))
		"portal_start":
			return escape.start(pid, _v2i(cmd["origin"]))
		"portal_next_stage":
			return escape.next_stage(pid)
		"portal_work":
			return unit_svc.command_portal_work(pid)
		"death_choice":
			return unit_svc.choose_afterlife(pid, str(cmd["choice"]))
		"enter_house":
			return house.command_enter(pid)
		"exit_house":
			return house.exit_house(pid)
		"house_repair":
			return house.press_repair(pid)
		"troll_skill":
			return troll.cast(unit_of(pid), str(cmd["skill"]))
		"soul_skill":
			return soul.cast(pid, str(cmd["skill"]), int(cmd.get("target_id", -1)))
		"soul_upgrade":
			return soul.upgrade(pid, str(cmd["skill"]))
		"set_troll_ai":
			var u: UnitState = units.get(players[pid].unit_id) if players.has(pid) else null
			if u == null or u.team != "trolls":
				return {"ok": false, "reason": "not_a_troll_unit"}
			u.ai_enabled = bool(cmd["enabled"])
			if not u.ai_enabled:
				unit_svc.set_order(u, {"type": "idle"})
			return {"ok": true}
		"debug_grant":
			economy.grant(pid, int(cmd.get("gold", 0)), int(cmd.get("wood", 0)), "debug")
			return {"ok": true}
		"debug_kill":
			var du: UnitState = units.get(players[pid].unit_id) if players.has(pid) else null
			if du:
				unit_svc.kill_unit(du)
			return {"ok": true}
		"debug_set_time":
			tick = int(float(cmd["sec"]) * tick_rate)
			return {"ok": true}
	return {"ok": false, "reason": "unknown_command"}


static func _v2i(v) -> Vector2i:
	if v is Vector2i:
		return v
	return Vector2i(int(v[0]), int(v[1]))


# ---------- 時間推進 ----------

func step() -> void:
	if is_over():
		return
	tick += 1
	events.current_tick = tick
	var tu: UnitState = units.get(players[TROLL_PLAYER_ID].unit_id)
	if tu and not tu.spawned and tick >= troll_spawn_tick:
		tu.spawned = true
		events.emit_event("troll_spawned", {"unit_id": tu.id})
	visibility.recompute()
	house.tick_gates()
	unit_svc.tick_units()
	troll.tick()
	soul.tick()
	building_svc.tick_jobs()
	escape.tick()
	repair.tick_repairs()
	house.tick_repairs()
	combat.tick_towers()
	if tick % tick_rate == 0:
		economy.produce_per_second()
	match_svc.check_end_of_tick()


func run_seconds(sec: float) -> void:
	for i in int(round(sec * tick_rate)):
		if is_over():
			return
		step()


# ---------- 查詢（給 UI） ----------

func building_at(c: Vector2i) -> BuildingInstance:
	return buildings.get(grid.occupant(c))


func unit_of(pid: int) -> UnitState:
	var p: PlayerAccount = players.get(pid)
	return units.get(p.unit_id) if p else null
