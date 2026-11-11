extends "res://tests/test_case.gd"
## 角色設計 V0.7：樹樁門、入屋、修復鈕、巨魔等級與技能、靈魂技能。
## 精靈 1 的基地：內部 x30..41 / y1..8，樹樁門在 (35..36, 9)。巨魔巢穴 x1..4 / y14..17。

const GATE_CELL := Vector2i(35, 9)


func test_gates_created_from_map() -> void:
	var sim := new_sim()
	eq(sim.house.gate_ids.size(), 3, "三個基地各一扇樹樁門")
	var owners := []
	for pid in [1, 2, 3]:
		var g := sim.house.gate_of(pid)
		check(g != null, "精靈 %d 有門" % pid)
		if g:
			owners.append(g.owner_player_id)
			eq(g.state, BuildingInstance.ST_GATE_OPEN, "開局門是開的")
	eq(owners, [1, 2, 3], "門屬於最近的精靈")
	check(sim.grid.is_walkable(GATE_CELL), "開著的門可以通行")
	eq(sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [35, 9]})["reason"], "gate_cell", "門格不能蓋建築")


func test_enter_house_closes_gate_and_boosts_gold() -> void:
	var sim := new_sim()
	var house := add_building(sim, 1, "elf_house", Vector2i(31, 2), 1)
	check(sim.submit({"type": "enter_house", "player_id": 1})["ok"], "下令入屋")
	check(run_until(sim, func(): return sim.house.is_inside(1), 10), "精靈走到樹屋旁進去")
	sim.step()
	var g := sim.house.gate_of(1)
	eq(g.state, BuildingInstance.ST_GATE_CLOSED, "入屋後門關上")
	check(not sim.grid.is_walkable(GATE_CELL), "關著的門擋路（巨魔與精靈都過不去）")
	run_until(sim, func(): return sim.tick % 10 == 0, 1)
	set_res(sim, 1, 0, 0)
	sim.run_seconds(4)
	eq(sim.players[1].gold, 12, "屋內樹屋 Lv1 每秒 2×150% = 3 金")
	var t := spawn_troll(sim, Vector2i(35, 12))
	eq(sim.submit({"type": "attack", "player_id": MatchSim.TROLL_PLAYER_ID, "target_kind": "unit", "target_id": sim.unit_of(1).id})["reason"], "target_not_attackable", "屋內精靈不能被攻擊")
	check(sim.submit({"type": "attack", "player_id": MatchSim.TROLL_PLAYER_ID, "target_kind": "building", "target_id": g.instance_id})["ok"], "關著的門可以被攻擊")
	sim.submit({"type": "exit_house", "player_id": 1})
	sim.step()
	eq(g.state, BuildingInstance.ST_GATE_OPEN, "出屋後門打開")
	check(sim.unit_of(1).on_map(), "精靈回到地圖上")
	check(house.is_alive() and t != null, "")


func test_gate_waits_until_nobody_stands_in_it() -> void:
	var sim := new_sim()
	var house := add_building(sim, 1, "elf_house", Vector2i(31, 2), 1)
	teleport(sim.unit_of(2), GATE_CELL)
	put_inside(sim, 1, house)
	sim.step()
	eq(sim.house.gate_of(1).state, BuildingInstance.ST_GATE_OPEN, "門口有人時不關門")
	teleport(sim.unit_of(2), Vector2i(35, 12))
	sim.step()
	eq(sim.house.gate_of(1).state, BuildingInstance.ST_GATE_CLOSED, "人走開後關門")


func test_gate_can_be_broken_and_stays_open_until_repaired() -> void:
	var sim := new_sim()
	var house := add_building(sim, 1, "elf_house", Vector2i(31, 2), 1)
	put_inside(sim, 1, house)
	sim.step()
	var g := sim.house.gate_of(1)
	var table: Array = sim.cfg["gate"]["hp_by_house_level"]
	eq(g.max_hp, int(table[1]), "門的 HP 依樹屋等級（Lv1）")
	var t := spawn_troll(sim, Vector2i(35, 10))
	eq(sim.combat.damage_building(t, g, 999999), int(table[1]), "只算有效傷害")
	eq(g.state, BuildingInstance.ST_GATE_BROKEN, "門被打破")
	check(sim.buildings.has(g.instance_id), "破門不會消失")
	check(sim.grid.is_walkable(GATE_CELL), "破門可以通行")
	sim.run_seconds(2)
	eq(g.state, BuildingInstance.ST_GATE_BROKEN, "精靈還在屋內，破門也保持開啟")
	g.hp = g.max_hp - 10
	check(sim.submit({"type": "house_repair", "player_id": 1})["ok"], "用修復鈕修門")
	sim.run_seconds(1)
	eq(g.state, BuildingInstance.ST_GATE_CLOSED, "修滿後恢復，主人在屋內就關上")
	house.level = 4
	house.max_hp = 1800
	sim.house.refresh_gate_hp(1)
	eq([g.hp, g.max_hp], [int(table[4]), int(table[4])], "樹屋升到 Lv4，門的 HP 跟著變（保留比例）")


func test_house_repair_button() -> void:
	var sim := new_sim()
	add_building(sim, 1, "elf_house", Vector2i(31, 2), 1)
	var w1 := add_building(sim, 1, "wall", Vector2i(33, 7), 1)
	var w2 := add_building(sim, 1, "wall", Vector2i(34, 7), 1)
	var other := add_building(sim, 2, "wall", Vector2i(36, 7), 1)
	w1.hp = 300
	w2.hp = 600
	other.hp = 100
	set_res(sim, 1, 50, 50)
	check(sim.submit({"type": "house_repair", "player_id": 1})["ok"], "按修復")
	sim.run_seconds(4)
	eq(w1.hp, 360, "Lv1：3 秒 × 20 HP，修 HP 比例最低的那塊")
	eq(w2.hp, 600, "一次只修一塊")
	eq(other.hp, 100, "不修別人的牆")
	eq([sim.players[1].gold, sim.players[1].wood], [58, 50], "完全免費（金幣只多了 4 秒樹屋產量）")
	eq(sim.submit({"type": "house_repair", "player_id": 1})["reason"], "cooldown", "Lv1 冷卻 6 秒")
	sim.run_seconds(2)
	check(sim.submit({"type": "house_repair", "player_id": 1})["ok"], "6 秒後可以再按")
	eq(sim.submit({"type": "house_repair", "player_id": 2})["reason"], "no_house", "沒有樹屋不能按")


func test_house_destroyed_ejects_and_stuns() -> void:
	var sim := new_sim()
	var house := add_building(sim, 1, "elf_house", Vector2i(31, 2), 1)
	put_inside(sim, 1, house)
	sim.step()
	var t := spawn_troll(sim, Vector2i(35, 12))
	sim.combat.damage_building(t, house, 99999)
	var u := sim.unit_of(1)
	check(u.on_map(), "樹屋被毀，精靈被彈出")
	check(u.stunned_until > sim.tick, "被彈出時暈眩")
	sim.step()
	eq(sim.house.gate_of(1).state, BuildingInstance.ST_GATE_OPEN, "門打開")


func test_elf_runs_faster() -> void:
	var sim := new_sim()
	eq(sim.unit_of(1).base_speed, 5.0, "精靈跑速 5.0 格/秒")


func test_troll_levels_and_minion_follow() -> void:
	var sim := new_sim()
	var t := troll(sim)
	var lv: Array = sim.cfg["troll"]["levels"]
	eq([t.level, t.max_hp, t.damage], [1, int(lv[0]["hp"]), int(lv[0]["damage"])], "Lv1 數值來自等級表")
	t.hp = 700
	sim.troll.add_xp(int(lv[0]["xp"]), "test")
	eq([t.level, t.max_hp, t.hp, t.damage], [2, int(lv[1]["hp"]), 700 + int(lv[1]["hp"]) - int(lv[0]["hp"]), int(lv[1]["damage"])], "升 Lv2：血量上限提高，當下血量加上差額")
	var wall := add_building(sim, 1, "wall", Vector2i(33, 5), 1)
	spawn_troll(sim, Vector2i(10, 12))
	sim.combat.damage_building(t, wall, 100)
	eq(t.xp, int(100 * float(sim.cfg["troll"]["xp_per_effective_hp"])), "對建築的有效傷害換成經驗")
	sim.troll.add_xp(int(lv[1]["xp"]) + int(lv[2]["xp"]) + int(lv[3]["xp"]) - t.xp, "test")
	eq(t.level, 5, "累積經驗連升到 Lv5")
	sim.submit({"type": "debug_kill", "player_id": 2})
	sim.submit({"type": "death_choice", "player_id": 2, "choice": "minion"})
	var m := sim.unit_of(2)
	eq([m.level, m.max_hp, m.damage], [3, int(lv[2]["hp"]) * 45 / 100, int(lv[2]["damage"]) * 45 / 100], "僕從 = 主巨魔等級 −2，數值 45%")
	sim.troll.add_xp(int(lv[4]["xp"]), "test")
	eq(m.level, 4, "主巨魔升級，僕從跟著升")


func test_troll_regen_nest_and_field() -> void:
	var sim := new_sim()
	var t := spawn_troll(sim, Vector2i(2, 15))
	t.hp = 300
	sim.run_seconds(1)
	check(absi(t.hp - (300 + t.max_hp * 8 / 100)) <= 1, "巢穴內每秒回 8%%（實際 %d）" % t.hp)
	teleport(t, Vector2i(20, 10))
	t.hp = 300
	t.last_damaged_tick = sim.tick
	sim.run_seconds(5)
	eq(t.hp, 300, "剛受傷時巢外不回血")
	sim.run_seconds(3)
	check(t.hp > 300 and t.hp <= 300 + t.max_hp * 3 / 100 + 1, "脫戰 6 秒後每秒回 1%")


func test_recall_channel_and_interrupt() -> void:
	var sim := new_sim()
	var t := spawn_troll(sim, Vector2i(20, 10))
	check(sim.submit({"type": "troll_skill", "player_id": MatchSim.TROLL_PLAYER_ID, "skill": "recall"})["ok"], "開始回巢")
	sim.run_seconds(2)
	sim.combat.damage_unit(null, t, 10)
	eq(t.channel_kind, "", "受傷打斷回巢")
	check(sim.submit({"type": "troll_skill", "player_id": MatchSim.TROLL_PLAYER_ID, "skill": "recall"})["ok"], "被打斷不進冷卻，可以再用")
	sim.run_seconds(3.1)
	check(sim.troll.in_nest(t), "引導 3 秒後回到巢穴")
	eq(sim.submit({"type": "troll_skill", "player_id": MatchSim.TROLL_PLAYER_ID, "skill": "recall"})["reason"], "already_in_nest", "已在巢穴")
	check(sim.troll.cooldown_left_sec(t, "recall") > 39.0, "成功回巢後冷卻 40 秒")


func test_smash_and_skill_unlocks() -> void:
	var sim := new_sim()
	var wall := add_building(sim, 1, "wall", Vector2i(20, 12), 1)
	var t := spawn_troll(sim, Vector2i(20, 13))
	eq(sim.submit({"type": "troll_skill", "player_id": MatchSim.TROLL_PLAYER_ID, "skill": "roar"})["reason"], "skill_locked", "怒吼 Lv3 才解鎖")
	eq(sim.submit({"type": "troll_skill", "player_id": MatchSim.TROLL_PLAYER_ID, "skill": "rampage"})["reason"], "skill_locked", "狂暴 Lv6 才解鎖")
	sim.submit({"type": "troll_skill", "player_id": MatchSim.TROLL_PLAYER_ID, "skill": "smash"})
	sim.submit({"type": "attack", "player_id": MatchSim.TROLL_PLAYER_ID, "target_kind": "building", "target_id": wall.instance_id})
	run_until(sim, func(): return sim.events.count("building_damaged") >= 2, 5)
	var hits := sim.events.find_all("building_damaged")
	eq(hits[0]["data"]["amount"], t.damage * 3, "重擊：第一下 3 倍")
	eq(hits[1]["data"]["amount"], t.damage, "第二下恢復正常")
	check(t.alive, "")


func test_roar_pauses_repair_and_construction() -> void:
	var sim := new_sim()
	add_building(sim, 1, "elf_house", Vector2i(31, 2), 4)
	var wall := add_building(sim, 1, "wall", Vector2i(33, 7), 1)
	wall.hp = 100
	var t := spawn_troll(sim, Vector2i(33, 6))
	sim.troll.add_xp(600 + 900, "test")
	eq(t.level, 3, "Lv3")
	check(sim.submit({"type": "troll_skill", "player_id": MatchSim.TROLL_PLAYER_ID, "skill": "roar"})["ok"], "怒吼")
	sim.submit({"type": "house_repair", "player_id": 1})
	sim.run_seconds(1.4)
	eq(wall.hp, 100, "怒吼後 1.5 秒內不能修")
	sim.run_seconds(1.0)
	check(wall.hp > 100 and wall.hp < 100 + 65, "之後修復量 −30%")
	check(sim.unit_of(1).build_block_until > 0, "附近精靈的施工被暫停")


func test_rampage() -> void:
	var sim := new_sim()
	var t := spawn_troll(sim, Vector2i(20, 10))
	sim.troll.add_xp(600 + 900 + 1300 + 1800 + 2500, "test")
	eq(t.level, 6, "Lv6")
	check(sim.submit({"type": "troll_skill", "player_id": MatchSim.TROLL_PLAYER_ID, "skill": "rampage"})["ok"], "狂暴")
	eq(sim.troll.attack_interval(t), 6, "攻速 +50%：間隔 10 → 6 tick")
	var hp := t.hp
	sim.combat.damage_unit(null, t, 100)
	eq(hp - t.hp, 120, "受到傷害 +20%")


func test_soul_mark_root_and_points() -> void:
	var sim := new_sim()
	add_building(sim, 2, "watch_tower", Vector2i(20, 8), 1)
	var t := spawn_troll(sim, Vector2i(20, 12))
	sim.submit({"type": "debug_kill", "player_id": 1})
	sim.submit({"type": "death_choice", "player_id": 1, "choice": "soul"})
	teleport(sim.unit_of(1), Vector2i(20, 9))
	sim.step()
	check(sim.submit({"type": "soul_skill", "player_id": 1, "skill": "mark"})["ok"], "星光印記")
	var hp := t.hp
	sim.combat.damage_unit(null, t, 100)
	eq(hp - t.hp, 110, "被標記時塔傷害 +10%")
	check(sim.submit({"type": "soul_skill", "player_id": 1, "skill": "root"})["ok"], "藤蔓纏繞")
	eq(t.current_speed(sim.tick), 0.0, "定身時不能移動")
	sim.unit_of(1).skill_ready["root"] = 0
	eq(sim.submit({"type": "soul_skill", "player_id": 1, "skill": "root"})["reason"], "target_root_immune", "定身後 4 秒免疫")
	eq(sim.submit({"type": "soul_upgrade", "player_id": 1, "skill": "root"})["reason"], "no_soul_points", "還沒有點數")
	sim.run_seconds(90)
	check(sim.submit({"type": "soul_upgrade", "player_id": 1, "skill": "root"})["ok"], "90 秒得 1 點")
	eq(sim.unit_of(1).soul_skills["root"], 2, "藤蔓纏繞 Lv2")


func test_troll_ai_retreats_when_low() -> void:
	var sim := new_sim()
	var t := spawn_troll(sim, Vector2i(25, 11))
	t.ai_enabled = true
	t.hp = t.max_hp * 20 / 100
	check(run_until(sim, func(): return sim.troll.in_nest(t), 15), "殘血時 AI 回巢")
	check(run_until(sim, func(): return t.ai_mode == "", 20), "補到 95% 再出發")


func test_troll_ai_ignores_hidden_elf() -> void:
	var sim := new_sim()
	var house := add_building(sim, 1, "elf_house", Vector2i(31, 2), 1)
	put_inside(sim, 1, house)
	var t := spawn_troll(sim, Vector2i(33, 6))
	t.ai_enabled = true
	sim.run_seconds(3)
	check(sim.players[1].alive_original, "屋內精靈不會被殺")
	check(t.ai_target.get("target_kind", "") != "unit" or t.ai_target.get("target_id") != sim.unit_of(1).id, "AI 不會鎖定屋內精靈")


func test_build_from_inside_house() -> void:
	var sim := new_sim()
	var house := add_building(sim, 1, "elf_house", Vector2i(31, 2), 1)
	put_inside(sim, 1, house)
	sim.step()
	var r := sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [34, 7]})
	check(r["ok"], "在屋內可以下令蓋基地裡的建築：%s" % str(r))
	check(sim.house.is_inside(1), "不會被迫出屋")
	check(run_until(sim, func(): return sim.buildings[r["instance_id"]].state == BuildingInstance.ST_ACTIVE, 10), "遠端施工會完工")
	eq(sim.house.gate_of(1).state, BuildingInstance.ST_GATE_CLOSED, "門一直關著")
	eq(sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [30, 14]})["reason"], "builder_cannot_reach", "門關著時蓋不到基地外面")
	sim.submit({"type": "exit_house", "player_id": 1})
	sim.step()
	check(sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [30, 14]})["ok"], "出屋（門打開）後可以到外面蓋")


func test_elf_bot_builds_and_hides() -> void:
	var sim := new_sim()
	var bot := ElfBot.new(sim, [1, 2, 3])
	for i in 1200:
		sim.step()
		bot.tick()
	for pid in [1, 2, 3]:
		check(sim.house.house_level(pid) >= 2, "電腦精靈 %d 會蓋並升級樹屋" % pid)
		check(sim.house.is_inside(pid), "電腦精靈 %d 會躲進屋裡" % pid)
		check(sim.building_svc.count_owned(pid, "arrow_tower") >= 1, "電腦精靈 %d 會蓋箭塔" % pid)
