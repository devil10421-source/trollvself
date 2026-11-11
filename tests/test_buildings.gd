extends "res://tests/test_case.gd"
## 規格第 7 節 1～6 項，加上數值表讀取與取消退款。
## 測試地圖：精靈 1 出生於 (35,4)，所在基地內部 x30..41 / y1..8。


func test_data_table_matches_spec() -> void:
	var defs := DefinitionDB.load_default()
	check(defs.is_valid(), "數值表驗證失敗：%s" % str(defs.errors))
	var buildable := 0
	for id in defs.building_order:
		if defs.get_def(id).buildable:
			buildable += 1
	eq(buildable, 9, "首版應有 9 種可建造建築（另有地圖自動生成的樹樁門）")
	var h := defs.get_def("elf_house")
	eq(h.level(4)["cost_g"], 1200, "樹屋 Lv4 追加金幣")
	eq(h.level(4)["gold_per_sec"], 11, "樹屋 Lv4 產量")
	eq(h.level(3)["time_ticks"], 300, "樹屋 Lv3 時間 30 秒 = 300 tick")
	eq(defs.get_def("wall").max_per_player, 18, "城牆上限")
	eq(defs.get_def("arrow_tower").level(1)["attack"]["interval_ticks"], 15, "箭塔 1.5 秒")
	var p := defs.get_def("escape_portal")
	var g := 0
	var w := 0
	var t := 0.0
	for st in p.stages:
		g += st["cost_g"]
		w += st["cost_w"]
		t += st["time_sec"]
	eq([g, w, t], [6500, 1300, 190.0], "傳送門三階段合計")
	check(not p.targetable_by_enemies and not p.damageable, "傳送門不可被選為目標、不可受傷")


func test_same_cell_and_duplicate_request() -> void:
	var sim := new_sim()
	var r1 := sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [33, 4], "request_id": "req-1"})
	check(r1["ok"], "第一次建造應成功：%s" % str(r1))
	var gold_after: int = sim.players[1].gold
	var r2 := sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [33, 4], "request_id": "req-1"})
	check(r2.get("duplicate", false), "相同 request_id 應回傳第一次結果")
	eq(sim.players[1].gold, gold_after, "重送請求不可再扣款")
	var r3 := sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [33, 4]})
	eq(r3["reason"], "occupied", "同一格不能有兩座建築")
	var r4 := sim.submit({"type": "build", "player_id": 1, "def_id": "elf_house", "origin": [32, 3]})
	eq(r4["reason"], "occupied", "2×2 占格與城牆重疊應被拒")
	eq(player_buildings(sim).size(), 1, "只能有一座建築")
	eq(sim.players[1].gold, 250 - 40, "只扣一次 40 金")
	# 不能蓋在單位身上、地形上、出生區
	eq(sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [35, 4]})["reason"], "spawn_area", "精靈出生點不可建造")
	eq(sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [29, 4]})["reason"], "blocked_terrain", "森林格不可建造")
	eq(sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [2, 15]})["reason"], "spawn_area", "巨魔出生區不可建造")


func test_insufficient_resources_and_tunable_costs() -> void:
	var sim := new_sim()
	set_res(sim, 1, 30, 100)
	var r := sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [33, 4]})
	eq(r["reason"], "insufficient_resources", "金幣不足應被拒")
	eq([sim.players[1].gold, sim.players[1].wood], [30, 100], "被拒不可扣款")
	# 資料可直接調整，不改核心程式
	sim.defs.get_def("wall").levels[0]["cost_g"] = 7
	r = sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [33, 4]})
	check(r["ok"], "調低成本後應可建造")
	eq(sim.players[1].gold, 23, "依調整後成本扣款")
	var sim2 := new_sim({"start_gold": 999})
	eq(sim2.players[2].gold, 999, "初始資源由設定檔決定")


func test_production_rates_and_owner_death() -> void:
	var sim := new_sim()
	var house := add_building(sim, 1, "elf_house", Vector2i(31, 2), 1)
	set_res(sim, 1, 0, 0)
	sim.run_seconds(3)
	eq(sim.players[1].gold, 6, "Lv1 每秒 2 金")
	set_res(sim, 1, 180, 30)
	check(sim.submit({"type": "upgrade", "player_id": 1, "instance_id": house.instance_id})["ok"], "升級 Lv2")
	eq(sim.players[1].gold, 0, "升級扣 180 金")
	sim.run_seconds(5)
	eq(sim.players[1].gold, 10, "升級期間仍以舊等級每秒 2 金生產")
	check(run_until(sim, func(): return house.level == 2, 30), "升級應完成")
	var before: int = sim.players[1].gold
	sim.run_seconds(10)
	eq(sim.players[1].gold - before, 40, "Lv2 每秒 4 金")
	var grove := add_building(sim, 1, "lumber_grove", Vector2i(38, 2), 1)
	var wood_before: int = sim.players[1].wood
	sim.run_seconds(4)
	eq(sim.players[1].wood - wood_before, 4, "林場 Lv1 每秒 1 木")
	sim.submit({"type": "debug_kill", "player_id": 1})
	var g: int = sim.players[1].gold
	var w: int = sim.players[1].wood
	sim.run_seconds(5)
	eq([sim.players[1].gold, sim.players[1].wood], [g, w], "主人死亡後立即停產")
	check(grove.is_alive() and house.is_alive(), "建築不會因主人死亡消失")


func test_builder_must_be_present() -> void:
	var sim := new_sim()
	var r := sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [31, 7]})
	var inst: BuildingInstance = sim.buildings[r["instance_id"]]
	check(run_until(sim, func(): return inst.job_progress_ticks > 0, 10), "精靈走到旁邊後開始施工")
	sim.submit({"type": "move", "player_id": 1, "cell": [40, 1]})
	sim.run_seconds(3)
	var p := inst.job_progress_ticks
	sim.run_seconds(2)
	eq(inst.job_progress_ticks, p, "建造者離開時施工暫停")
	sim.submit({"type": "resume_build", "player_id": 1, "instance_id": inst.instance_id})
	check(run_until(sim, func(): return inst.state == BuildingInstance.ST_ACTIVE, 20), "續建後完工")
	eq(inst.hp, inst.max_hp, "未受傷完工為滿血")


func test_cancel_refund() -> void:
	var sim := new_sim()
	var r := sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [33, 4]})
	var res := sim.submit({"type": "cancel", "player_id": 1, "instance_id": r["instance_id"]})
	eq([res["refund_g"], res["refund_w"]], [20, 7], "未施工取消：退 50%（無條件捨去）")
	eq(player_buildings(sim).size(), 0, "取消後建築移除")
	eq(sim.grid.occupant(Vector2i(33, 4)), -1, "占格釋放")


func test_destroyed_hall_does_not_unlock_for_free() -> void:
	var sim := new_sim()
	add_building(sim, 1, "elf_house", Vector2i(31, 2), 2)
	var hall := add_building(sim, 1, "craft_hall", Vector2i(38, 6), 1)
	var wa := add_building(sim, 1, "wall", Vector2i(31, 6), 1)
	var wb := add_building(sim, 1, "wall", Vector2i(32, 6), 1)
	set_res(sim, 1, 5000, 5000)
	check(sim.submit({"type": "upgrade", "player_id": 1, "instance_id": wa.instance_id})["ok"], "有大廳 Lv1 可升城牆 Lv2")
	check(run_until(sim, func(): return wa.level == 2, 20), "城牆 A 升到 Lv2")
	var t := spawn_troll(sim, Vector2i(10, 12))
	sim.combat.damage_building(t, hall, 999999)
	check(not hall.is_alive(), "大廳被摧毀")
	eq(wa.level, 2, "既有升級不倒退")
	var gold: int = sim.players[1].gold
	var r := sim.submit({"type": "upgrade", "player_id": 1, "instance_id": wb.instance_id})
	eq(r["reason"], "requirement", "大廳沒了不能再發起 Lv2 升級")
	eq(sim.players[1].gold, gold, "被拒不扣款")
	var nh := sim.submit({"type": "build", "player_id": 1, "def_id": "craft_hall", "origin": [38, 6]})
	check(nh["ok"], "可重建大廳")
	eq(sim.submit({"type": "upgrade", "player_id": 1, "instance_id": wb.instance_id})["reason"], "requirement", "大廳施工中仍不算 Lv1")
	check(run_until(sim, func(): return sim.buildings[nh["instance_id"]].level == 1, 40), "重建完成")
	check(sim.submit({"type": "upgrade", "player_id": 1, "instance_id": wb.instance_id})["ok"], "重建後才可升級")


func test_upgrade_keeps_hp_ratio() -> void:
	var sim := new_sim()
	add_building(sim, 1, "craft_hall", Vector2i(38, 6), 2)
	var wall := add_building(sim, 1, "wall", Vector2i(31, 6), 2)
	wall.hp = 800
	set_res(sim, 1, 5000, 5000)
	check(sim.submit({"type": "upgrade", "player_id": 1, "instance_id": wall.instance_id})["ok"], "升 Lv3")
	check(run_until(sim, func(): return wall.level == 3, 30), "升級完成")
	eq([wall.hp, wall.max_hp], [1800, 3600], "50% 血量升級後仍為 50%")


func test_repair_is_free_and_walls_need_house_button() -> void:
	var sim := new_sim()
	var tower := add_building(sim, 1, "arrow_tower", Vector2i(33, 5), 1)
	tower.hp = 300
	set_res(sim, 1, 100, 100)
	check(sim.submit({"type": "repair", "player_id": 1, "instance_id": tower.instance_id})["ok"], "精靈可手動修塔")
	check(run_until(sim, func(): return tower.hp == tower.max_hp, 30), "修滿")
	eq([sim.players[1].gold, sim.players[1].wood], [100, 100], "修復完全免費")
	var wall := add_building(sim, 1, "wall", Vector2i(31, 5), 1)
	wall.hp = 100
	eq(sim.submit({"type": "repair", "player_id": 1, "instance_id": wall.instance_id})["reason"], "walls_use_house_button", "城牆不能手動修")


func test_repair_post_speed() -> void:
	var sim := new_sim()
	var p := Vector2(34.5, 5.5)
	eq(sim.repair.aura_bonus_at(p), 0, "沒有修繕站時無加成")
	add_building(sim, 1, "repair_post", Vector2i(36, 6), 1)
	add_building(sim, 2, "repair_post", Vector2i(37, 6), 1)
	eq(sim.repair.aura_bonus_at(p), 25, "修繕站範圍內 +25%，兩座不疊加")
	var tower := add_building(sim, 1, "arrow_tower", Vector2i(33, 5), 1)
	tower.hp = 100
	sim.repair.restore_tick(tower, 40, 25)
	eq(tower.hp, 105, "40 HP/秒 × 125% = 每 tick 5")


func test_frost_does_not_stack_and_tower_targets() -> void:
	var sim := new_sim()
	add_building(sim, 1, "frost_tower", Vector2i(30, 12), 1)
	add_building(sim, 2, "frost_tower", Vector2i(31, 12), 2)
	var t := spawn_troll(sim, Vector2i(30, 14))
	sim.step()
	eq(t.strongest_slow(sim.tick), 25, "兩座冰霜塔只取最強 25%")
	check(absf(t.current_speed(sim.tick) - t.base_speed * 0.75) < 0.0001, "速度 = 75%")
	# 不可見目標
	var sim2 := new_sim()
	var arrow := add_building(sim2, 1, "arrow_tower", Vector2i(24, 12), 3)  # 射程 7，自身視野 4
	var t2 := spawn_troll(sim2, Vector2i(24, 18))
	sim2.run_seconds(3)
	eq(t2.hp, t2.max_hp, "射程內但不可見的巨魔不會被打")
	add_building(sim2, 1, "watch_tower", Vector2i(23, 16), 1)
	sim2.run_seconds(2)
	check(t2.hp < t2.max_hp, "瞭望塔提供視野後箭塔開火")
	sim2.unit_svc.kill_unit(t2)
	var fired := sim2.events.count("tower_fired")
	sim2.run_seconds(3)
	eq(sim2.events.count("tower_fired"), fired, "不攻擊已死亡目標")
	check(arrow.is_alive(), "")


func test_tower_priority() -> void:
	var sim := new_sim()
	var tower := add_building(sim, 1, "arrow_tower", Vector2i(30, 12), 1)
	add_building(sim, 1, "watch_tower", Vector2i(30, 14), 1)
	var t := spawn_troll(sim, Vector2i(33, 12))
	var m := sim.unit_svc.spawn_unit(UnitState.KIND_MINION, MatchSim.TROLL_PLAYER_ID, Vector2i(31, 13))
	sim.visibility.recompute()
	eq(sim.combat.pick_tower_target(tower, 5).id, m.id, "沒人打建築時打最近的")
	t.last_building_attack_tick = sim.tick
	eq(sim.combat.pick_tower_target(tower, 5).id, t.id, "優先打正在攻擊建築的敵人")


func test_damage_reward_only_effective_hp() -> void:
	var sim := new_sim()
	var wall := add_building(sim, 1, "wall", Vector2i(33, 5), 1)
	wall.hp = 30
	var t := spawn_troll(sim, Vector2i(10, 12))
	eq(sim.combat.damage_building(t, wall, 45), 30, "過量傷害只算實際扣除的 30")
	eq(sim.combat.damage_building(t, wall, 45), 0, "已倒塌建築鞭屍無效")
	eq(sim.players[MatchSim.TROLL_PLAYER_ID].troll_gold, 3, "收益按有效傷害 30 × 0.1")
