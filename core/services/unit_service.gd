class_name UnitService
extends RefCounted
## 單位移動、指令執行、死亡與轉生、測試用巨魔 AI。
## 精靈/靈魂：4 向 BFS，建築一律阻擋。
## 巨魔方：4 向加權最短路（Dijkstra）。可攻擊建築視為「要花時間打穿」的高成本格；
##          傳送門與地形不可通過、也不能攻擊。路徑上遇到可攻擊建築就先打它。

var sim: MatchSim
var _respawn_at := {}   # unit_id -> tick


func _init(s: MatchSim) -> void:
	sim = s


# ---------- 建立 / 死亡 ----------

func spawn_unit(kind: String, pid: int, cell: Vector2i) -> UnitState:
	var u := UnitState.new()
	u.id = sim.next_id()
	u.kind = kind
	u.player_id = pid
	u.pos = GridMath.cell_center(cell)
	var c: Dictionary = sim.cfg[kind]
	u.base_speed = float(c.get("move_speed", 4.0))
	u.vision = float(c.get("vision", 6))
	match kind:
		UnitState.KIND_ELF:
			u.team = "elves"
			u.max_hp = int(c["hp"])
		UnitState.KIND_SOUL:
			u.team = "elves"
			u.max_hp = 1
			u.energy_max = float(c.get("energy_max", 100))
			u.energy = u.energy_max
		UnitState.KIND_TROLL, UnitState.KIND_MINION:
			u.team = "trolls"
			u.level = 1 if kind == UnitState.KIND_TROLL else sim.troll.minion_level()
			u.alive = false  # apply_stats 在未存活時直接給滿血
			sim.troll.apply_stats(u)
			u.alive = true
			u.attack_interval_ticks = maxi(1, sim.defs.sec_to_ticks(float(c["attack_interval"])))
			u.attack_range = float(c.get("attack_range", 1.5))
			u.reward_per_hp = float(c.get("reward_gold_per_effective_hp", 0.0))
	u.hp = u.max_hp
	sim.units[u.id] = u
	return u


func set_order(u: UnitState, order: Dictionary) -> void:
	if u.inside_house != -1 and ["move", "build", "repair", "portal_work"].has(str(order.get("type", ""))):
		sim.house.exit_house(u.player_id)
	u.order = order
	u.path = []
	u.repath_cooldown = 0


func kill_unit(u: UnitState) -> void:
	if not u.alive:
		return
	u.alive = false
	u.path = []
	var p: PlayerAccount = sim.players.get(u.player_id)
	if u.kind == UnitState.KIND_ELF and p:
		p.alive_original = false
		p.afterlife = "pending"
		p.job_instance_id = -1
		p.set_meta("death_cell", u.cell())
		sim.events.emit_event("elf_died", {"player_id": p.id, "unit_id": u.id})
	else:
		sim.events.emit_event("unit_died", {"unit_id": u.id, "kind": u.kind})
		if u.team == "trolls":
			u.channel_kind = ""
			u.channel_until = -1
			u.rampage_until = -1
			u.smash_ready = false
			u.ai_mode = ""
			_respawn_at[u.id] = sim.tick + sim.troll.respawn_ticks(u)


## 精靈死亡後選擇陣營：soul（精靈方靈魂）或 minion（巨魔方僕從）。
func choose_afterlife(pid: int, choice: String) -> Dictionary:
	var p: PlayerAccount = sim.players.get(pid)
	if p == null or p.afterlife != "pending":
		return {"ok": false, "reason": "no_pending_choice"}
	var u: UnitState
	if choice == "soul":
		var c: Vector2i = p.get_meta("death_cell", sim.grid.elf_spawns.get(1, Vector2i.ZERO))
		u = spawn_unit(UnitState.KIND_SOUL, pid, _nearest_walkable(c))
	elif choice == "minion":
		u = spawn_unit(UnitState.KIND_MINION, pid, sim.grid.troll_spawn_cells[0])
		u.ai_enabled = true
	else:
		return {"ok": false, "reason": "invalid_choice"}
	p.afterlife = choice
	p.unit_id = u.id
	sim.events.emit_event("afterlife_chosen", {"player_id": pid, "choice": choice, "unit_id": u.id})
	return {"ok": true, "unit_id": u.id}


func _nearest_walkable(c: Vector2i) -> Vector2i:
	var r: Dictionary = sim.grid.bfs_path(c, func(x): return sim.grid.is_walkable(x))
	if r["found"] and not r["path"].is_empty():
		return r["path"][-1]
	return c


# ---------- 指令 ----------

func command_move(pid: int, cell: Vector2i) -> Dictionary:
	var u := _controlled(pid)
	if u == null:
		return {"ok": false, "reason": "no_unit"}
	if not sim.grid.in_bounds(cell) or sim.grid.is_terrain_blocked(cell):
		return {"ok": false, "reason": "invalid_destination"}
	var p: PlayerAccount = sim.players[pid]
	if u.kind == UnitState.KIND_ELF:
		p.job_instance_id = -1  # 走開 = 放下手上的施工（工地保留，可續建）
	set_order(u, {"type": "move", "cell": cell})
	return {"ok": true}


func command_attack(pid: int, target_kind: String, target_id: int) -> Dictionary:
	var u := _controlled(pid)
	if u == null or u.team != "trolls":
		return {"ok": false, "reason": "not_a_troll_unit"}
	if target_kind == "building":
		var inst: BuildingInstance = sim.buildings.get(target_id)
		if not sim.combat.is_attackable_building(inst):
			# 傳送門與一切不可攻擊目標在伺服器端拒絕
			sim.events.emit_event("attack_rejected", {"unit_id": u.id, "target_id": target_id, "reason": "target_not_attackable"})
			return {"ok": false, "reason": "target_not_attackable"}
	elif target_kind == "unit":
		var t: UnitState = sim.units.get(target_id)
		if t == null or not t.on_map() or t.team == u.team or t.kind == UnitState.KIND_SOUL:
			return {"ok": false, "reason": "target_not_attackable"}
	else:
		return {"ok": false, "reason": "invalid_target"}
	set_order(u, {"type": "attack", "target_kind": target_kind, "target_id": target_id})
	return {"ok": true}


func command_portal_work(pid: int) -> Dictionary:
	var u := _controlled(pid)
	if u == null or u.kind != UnitState.KIND_ELF:
		return {"ok": false, "reason": "not_living_elf"}
	if sim.escape.portal_inst() == null:
		return {"ok": false, "reason": "no_portal"}
	sim.players[pid].job_instance_id = -1
	set_order(u, {"type": "portal_work"})
	return {"ok": true}


func _controlled(pid: int) -> UnitState:
	var p: PlayerAccount = sim.players.get(pid)
	if p == null:
		return null
	var u: UnitState = sim.units.get(p.unit_id)
	if u == null or not u.alive or not u.spawned:
		return null
	return u


# ---------- 每 tick ----------

func tick_units() -> void:
	var ids := sim.units.keys()
	ids.sort()
	for uid in ids:
		var u: UnitState = sim.units[uid]
		if not u.alive:
			if _respawn_at.has(uid) and sim.tick >= _respawn_at[uid]:
				_respawn_at.erase(uid)
				u.alive = true
				u.hp = u.max_hp
				u.last_damaged_tick = -100000
				u.pos = GridMath.cell_center(sim.grid.troll_spawn_cells[0])
				set_order(u, {"type": "idle"})
				sim.events.emit_event("unit_respawned", {"unit_id": uid})
			continue
		if not u.spawned or u.inside_house != -1:
			continue
		if u.kind == UnitState.KIND_SOUL:
			u.energy = minf(u.energy_max, u.energy + float(sim.cfg["soul"]["energy_regen_per_sec"]) / sim.tick_rate)
		if u.attack_cooldown > 0:
			u.attack_cooldown -= 1
		if u.ai_enabled and u.team == "trolls" and (sim.tick + uid) % sim.tick_rate == 0:
			if not sim.troll.ai_tactics(u):
				_ai_think(u)
		if u.channel_kind != "" or sim.tick < u.stunned_until:
			continue  # 引導回巢中 / 暈眩：不動作
		_execute(u)


func _execute(u: UnitState) -> void:
	var o := u.order
	match str(o.get("type", "idle")):
		"idle":
			pass
		"move":
			var target: Vector2i = o["cell"]
			if u.cell() == target and u.path.is_empty():
				set_order(u, {"type": "idle"})
				return
			_go(u, func(c): return c == target)
		"build", "repair":
			var inst: BuildingInstance = sim.buildings.get(o["instance_id"])
			if inst == null:
				set_order(u, {"type": "idle"})
				return
			var rng: int = sim.building_svc.builder_range() if o["type"] == "build" else sim.repair.repair_range()
			_approach_rect(u, inst.origin, inst.size, rng)
		"portal_work":
			var p: BuildingInstance = sim.escape.portal_inst()
			if p == null:
				set_order(u, {"type": "idle"})
				return
			_approach_rect(u, p.origin, p.size, sim.escape.build_range())
		"enter_house":
			var h: BuildingInstance = sim.buildings.get(o["instance_id"])
			if h == null or not h.is_functional():
				set_order(u, {"type": "idle"})
				return
			var er: int = sim.house.enter_range()
			if GridMath.cheb_cell_to_rect(u.cell(), h.origin, h.size) <= er:
				sim.house.do_enter(u, h)
				return
			_go(u, func(c): return GridMath.cheb_cell_to_rect(c, h.origin, h.size) <= er)
		"attack":
			_execute_attack(u)


## 走到距離矩形 Chebyshev ≤ rng 的位置。已到則停。
func _approach_rect(u: UnitState, origin: Vector2i, size: Vector2i, rng: int) -> void:
	if GridMath.cheb_cell_to_rect(u.cell(), origin, size) <= rng and _at_center(u):
		u.path = []
		return
	_go(u, func(c): return GridMath.cheb_cell_to_rect(c, origin, size) <= rng)


func _at_center(u: UnitState) -> bool:
	return u.pos.distance_to(GridMath.cell_center(u.cell())) < 0.05


## 精靈方移動：必要時重算 BFS 路徑，然後前進一步。
func _go(u: UnitState, goal: Callable) -> void:
	if u.path.is_empty() or u.repath_cooldown <= 0:
		if u.path.is_empty() and goal.call(u.cell()):
			_step_toward(u, GridMath.cell_center(u.cell()))
			return
		var r: Dictionary = sim.grid.bfs_path(u.cell(), goal)
		u.path = r["path"]
		u.repath_cooldown = sim.tick_rate
		if not r["found"]:
			u.repath_cooldown = sim.tick_rate * 2
			return
	u.repath_cooldown -= 1
	_follow_path(u)


func _follow_path(u: UnitState) -> void:
	if u.path.is_empty():
		_step_toward(u, GridMath.cell_center(u.cell()))
		return
	var nxt: Vector2i = u.path[0]
	if not sim.grid.is_walkable(nxt):
		u.path = []  # 路被擋，下一 tick 重算
		return
	if _step_toward(u, GridMath.cell_center(nxt)):
		u.path.pop_front()


## 朝目標點移動一個 tick；到達回傳 true。
func _step_toward(u: UnitState, target: Vector2) -> bool:
	var step := u.current_speed(sim.tick) / sim.tick_rate
	var d := u.pos.distance_to(target)
	if d <= step:
		u.pos = target
		return true
	u.pos += (target - u.pos) / d * step
	return false


# ---------- 巨魔方 ----------

func _execute_attack(u: UnitState) -> void:
	var o := u.order
	var target_pos := Vector2.ZERO
	var in_range := false
	var goal: Callable
	if o["target_kind"] == "building":
		var inst: BuildingInstance = sim.buildings.get(o["target_id"])
		if not sim.combat.is_attackable_building(inst):
			set_order(u, {"type": "idle"})
			return
		in_range = GridMath.point_to_rect(u.pos, inst.origin, inst.size) <= u.attack_range
		var rng := u.attack_range - 0.01
		goal = func(c): return GridMath.point_to_rect(GridMath.cell_center(c), inst.origin, inst.size) <= rng
		if in_range:
			_strike(u, inst, null)
			return
	else:
		var t: UnitState = sim.units.get(o["target_id"])
		if t == null or not t.on_map():
			set_order(u, {"type": "idle"})
			return
		target_pos = t.pos
		if u.pos.distance_to(target_pos) <= u.attack_range:
			_strike(u, null, t)
			return
		var tc := t.cell()
		goal = func(c): return c == tc
	_troll_go(u, goal)


func _strike(u: UnitState, inst: BuildingInstance, t: UnitState) -> void:
	u.path = []
	if u.attack_cooldown > 0:
		return
	u.attack_cooldown = sim.troll.attack_interval(u)
	if inst:
		sim.combat.damage_building(u, inst, sim.troll.consume_smash(u, u.damage, true))
	else:
		sim.combat.damage_unit(u, t, u.damage)


func _troll_go(u: UnitState, goal: Callable) -> void:
	if u.path.is_empty() or u.repath_cooldown <= 0:
		u.path = troll_path(u, goal)
		u.repath_cooldown = sim.tick_rate / 2
	u.repath_cooldown -= 1
	if u.path.is_empty():
		_step_toward(u, GridMath.cell_center(u.cell()))
		return
	var nxt: Vector2i = u.path[0]
	var occ := sim.grid.occupant(nxt)
	if occ != -1:
		var inst: BuildingInstance = sim.buildings.get(occ)
		if sim.combat.is_attackable_building(inst):
			# 擋路的牆 / 建築：先打它
			if _step_toward(u, GridMath.cell_center(u.cell())) or _at_center(u):
				_strike(u, inst, null)
				u.path = [nxt]  # 保留方向，打穿後繼續
		else:
			u.path = []
		return
	if sim.grid.is_terrain_blocked(nxt):
		u.path = []
		return
	if _step_toward(u, GridMath.cell_center(nxt)):
		u.path.pop_front()


## 巨魔加權最短路。回傳不含起點的格列表；找不到回傳空陣列。
func troll_path(u: UnitState, goal: Callable) -> Array[Vector2i]:
	var res := troll_dijkstra(u)
	var g: TileGrid = sim.grid
	var dist: PackedInt32Array = res["dist"]
	var best := -1
	var best_d := 0x3fffffff
	for i in dist.size():
		if dist[i] < best_d:
			var c := Vector2i(i % g.width, i / g.width)
			if not g.occupancy.has(c) and goal.call(c):
				best_d = dist[i]
				best = i
	return _reconstruct(res["parent"], best, g.idx(u.cell()))


func _reconstruct(parent: PackedInt32Array, goal_idx: int, start_idx: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if goal_idx < 0:
		return out
	var w: int = sim.grid.width
	var i := goal_idx
	while i != start_idx and i >= 0:
		out.push_front(Vector2i(i % w, i / w))
		i = parent[i]
	return out


## 進入一格的成本（×10）：空地 10；可攻擊建築 10 + 打穿所需時間折算的步數；其餘不可通過。
func enter_cost(u: UnitState, c: Vector2i) -> int:
	var g: TileGrid = sim.grid
	if g.is_terrain_blocked(c):
		return -1
	var occ := g.occupant(c)
	if occ == -1:
		return 10
	var inst: BuildingInstance = sim.buildings.get(occ)
	if not sim.combat.is_attackable_building(inst):
		return -1
	var dps := float(u.damage) * sim.tick_rate / u.attack_interval_ticks
	var steps := float(inst.hp) / maxf(1.0, dps) * u.base_speed
	return 10 + int(steps * 10.0)


func troll_dijkstra(u: UnitState) -> Dictionary:
	var g: TileGrid = sim.grid
	var n := g.width * g.height
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(0x3fffffff)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var start := g.idx(u.cell())
	dist[start] = 0
	var heap: Array[Vector2i] = [Vector2i(0, start)]  # (cost, idx)
	while not heap.is_empty():
		var top := _heap_pop(heap)
		var i := top.y
		if top.x > dist[i]:
			continue
		var c := Vector2i(i % g.width, i / g.width)
		for d in GridMath.DIRS4:
			var nc: Vector2i = c + d
			if not g.in_bounds(nc):
				continue
			var cost := enter_cost(u, nc)
			if cost < 0:
				continue
			var ni := g.idx(nc)
			var nd := top.x + cost
			if nd < dist[ni]:
				dist[ni] = nd
				parent[ni] = i
				_heap_push(heap, Vector2i(nd, ni))
	return {"dist": dist, "parent": parent}


static func _heap_push(h: Array[Vector2i], v: Vector2i) -> void:
	h.append(v)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if h[p].x <= h[i].x:
			break
		var tmp := h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p


static func _heap_pop(h: Array[Vector2i]) -> Vector2i:
	var top := h[0]
	var last: Vector2i = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and h[l].x < h[m].x:
			m = l
		if r < n and h[r].x < h[m].x:
			m = r
		if m == i:
			break
		var tmp := h[m]
		h[m] = h[i]
		h[i] = tmp
		i = m
	return top


## 測試用巨魔 AI（不是正式 AI）：在「最近的存活原始精靈」與「最近的可攻擊建築」中，
## 依加權路徑成本選一個（精靈成本打 6 折，偏好追人）。
func _ai_think(u: UnitState) -> void:
	var res := troll_dijkstra(u)
	var dist: PackedInt32Array = res["dist"]
	var g: TileGrid = sim.grid
	var best_score := 1e18
	var best := {}
	for v in sim.units.values():
		var t: UnitState = v
		if not t.on_map() or t.kind != UnitState.KIND_ELF:
			continue
		var d := dist[g.idx(t.cell())]
		if d >= 0x3fffffff:
			continue
		var score := d * 0.6
		if score < best_score:
			best_score = score
			best = {"target_kind": "unit", "target_id": t.id}
	var bids := sim.buildings.keys()
	bids.sort()
	for bid in bids:
		var inst: BuildingInstance = sim.buildings[bid]
		if not sim.combat.is_attackable_building(inst):
			continue
		var d2 := 0x3fffffff
		for c in GridMath.rect_cells(inst.origin - Vector2i.ONE, inst.size + Vector2i(2, 2)):
			if g.in_bounds(c) and not g.occupancy.has(c):
				d2 = mini(d2, dist[g.idx(c)])
		if d2 >= 0x3fffffff:
			continue
		if d2 < best_score:
			best_score = d2
			best = {"target_kind": "building", "target_id": bid}
	u.ai_target = best
	if best.is_empty():
		return
	var o := u.order
	if o.get("type") == "attack" and o.get("target_kind") == best["target_kind"] and o.get("target_id") == best["target_id"]:
		return
	set_order(u, {"type": "attack", "target_kind": best["target_kind"], "target_id": best["target_id"]})
