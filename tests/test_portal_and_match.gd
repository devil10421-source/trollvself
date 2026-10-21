extends "res://tests/test_case.gd"
## 規格第 7 節 7～10 項：傳送門、勝負、靈魂/僕從。
## 測試地圖的保護區：x40..46 / y12..19；入口 (38..39, 15..16)。傳送門放在 (42,14)。

const PORTAL := [42, 14]
const IN_ZONE := Vector2i(41, 13)


func _portal_sim() -> MatchSim:
	var sim := new_sim()
	ready_for_portal(sim, 1, Vector2i(31, 2), Vector2i(38, 6))
	teleport(sim.unit_of(1), IN_ZONE)
	return sim


func test_map_protection_zone() -> void:
	var sim := new_sim()
	check(not sim.escape.zone_sealed(), "入口沒牆時，巨魔走得進保護區")
	add_building(sim, 1, "wall", Vector2i(38, 15), 1)
	check(not sim.escape.zone_sealed(), "只封一格仍未封閉")
	add_building(sim, 1, "wall", Vector2i(38, 16), 1)
	check(sim.escape.zone_sealed(), "兩格入口都封住後保護區封閉")


func test_portal_placement_rules() -> void:
	var sim := _portal_sim()
	sim.tick = sim.escape.unlock_tick() - 10
	eq(sim.submit({"type": "portal_start", "player_id": 1, "origin": PORTAL})["reason"], "time_locked", "12:00 前不能發起")
	sim.tick = sim.escape.unlock_tick()
	eq(sim.submit({"type": "portal_start", "player_id": 1, "origin": PORTAL})["reason"], "zone_not_sealed", "入口沒封牆不能建")
	seal_portal_zone(sim, 1)
	eq(sim.submit({"type": "portal_start", "player_id": 1, "origin": [30, 12]})["reason"], "outside_portal_zone", "一般空地不能建")
	eq(sim.submit({"type": "portal_start", "player_id": 1, "origin": [45, 14]})["reason"], "outside_portal_zone", "超出保護區邊界不能建")
	var sim_req := new_sim()
	sim_req.tick = sim_req.escape.unlock_tick()
	seal_portal_zone(sim_req, 1)
	add_building(sim_req, 1, "craft_hall", Vector2i(38, 6), 2)
	set_res(sim_req, 1, 20000, 5000)
	eq(sim_req.submit({"type": "portal_start", "player_id": 1, "origin": PORTAL})["reason"], "requirement", "缺樹屋 Lv4 不能建")
	var g: int = sim.players[1].gold
	var r := sim.submit({"type": "portal_start", "player_id": 1, "origin": PORTAL})
	check(r["ok"], "合法位置可建：%s" % str(r))
	eq(g - sim.players[1].gold, 1400, "第一階段扣 1400 金")
	teleport(sim.unit_of(2), Vector2i(41, 18))
	set_res(sim, 2, 20000, 5000)
	eq(sim.submit({"type": "portal_start", "player_id": 2, "origin": [42, 17]})["reason"], "portal_exists", "全隊只能一座")


func test_portal_stage_timing_pause_and_immunity() -> void:
	var sim := _portal_sim()
	seal_portal_zone(sim, 1)
	var pid: int = sim.submit({"type": "portal_start", "player_id": 1, "origin": PORTAL})["instance_id"]
	sim.run_seconds(44.9)
	eq(sim.escape.status, EscapeService.STATUS_BUILDING, "44.9 秒時第一階段尚未完成")
	sim.step()
	eq(sim.escape.status, EscapeService.STATUS_WAITING, "45 秒整完成第一階段")
	sim.run_seconds(5)
	eq(sim.escape.stage, 1, "未付款不進入下一階段")
	var g: int = sim.players[1].gold
	check(sim.submit({"type": "portal_next_stage", "player_id": 1})["ok"], "支付第二階段")
	eq(g - sim.players[1].gold, 2200, "第二階段扣 2200 金")
	eq(sim.events.count("portal_alert_trolls"), 1, "第二階段開始時提示巨魔")
	sim.run_seconds(10)
	var before := sim.escape.progress_milli
	# 精靈離開施工範圍 → 暫停但不倒退
	var u := sim.unit_of(1)
	teleport(u, Vector2i(30, 12))
	sim.unit_svc.set_order(u, {"type": "idle"})
	sim.run_seconds(8)
	eq(sim.escape.progress_milli, before, "離開施工範圍後進度暫停、不倒退")
	check(sim.events.count("escape_stage_interrupted") >= 1, "發出暫停事件")
	var paused_at := sim.escape.progress_milli
	teleport(u, IN_ZONE)
	# 巨魔破牆進入保護區：可以打精靈，但打門一律被拒、不影響進度
	var t := spawn_troll(sim, Vector2i(45, 19))
	var r := sim.submit({"type": "attack", "player_id": MatchSim.TROLL_PLAYER_ID, "target_kind": "building", "target_id": pid})
	eq(r["reason"], "target_not_attackable", "攻擊傳送門的指令被伺服器拒絕")
	var dmg := sim.combat.damage_building(t, sim.buildings[pid], 99999)
	eq(dmg, 0, "直接呼叫傷害也是 0")
	sim.run_seconds(2)
	eq(sim.escape.progress_milli, paused_at + 20000, "施工照常推進 2 秒")
	check(sim.buildings.has(pid), "傳送門不會被摧毀")
	for e in sim.events.find_all("building_damaged"):
		check(e["data"]["instance_id"] != pid, "傳送門不得觸發 building_damaged")
	check(sim.submit({"type": "attack", "player_id": MatchSim.TROLL_PLAYER_ID, "target_kind": "unit", "target_id": u.id})["ok"], "巨魔可以攻擊區內精靈")


func test_multi_builder_bonus() -> void:
	var sim := _portal_sim()
	eq([sim.escape.speed_bonus_percent(1), sim.escape.speed_bonus_percent(2), sim.escape.speed_bonus_percent(3), sim.escape.speed_bonus_percent(4)], [0, 15, 30, 30], "多人加速最高 30%")
	seal_portal_zone(sim, 1)
	sim.submit({"type": "portal_start", "player_id": 1, "origin": PORTAL})
	teleport(sim.unit_of(2), Vector2i(41, 18))
	teleport(sim.unit_of(3), Vector2i(46, 13))
	sim.step()
	eq(sim.escape.builders, 3, "三人都在範圍內")
	eq(sim.escape.progress_milli, 1300, "三人施工每 tick 1.3 倍")


func test_initiator_death_handover_and_escape_win() -> void:
	var sim := _portal_sim()
	seal_portal_zone(sim, 1)
	sim.submit({"type": "portal_start", "player_id": 1, "origin": PORTAL})
	check(run_until(sim, func(): return sim.escape.status == EscapeService.STATUS_WAITING, 50), "第一階段完成")
	sim.submit({"type": "debug_kill", "player_id": 1})
	check(sim.escape.portal_inst() != null, "發起者死亡傳送門不會消失")
	eq(sim.submit({"type": "portal_next_stage", "player_id": 1})["reason"], "not_living_elf", "死者不能付款")
	teleport(sim.unit_of(2), Vector2i(41, 18))
	set_res(sim, 2, 20000, 5000)
	check(sim.submit({"type": "portal_next_stage", "player_id": 2})["ok"], "其他存活精靈可接手付款")
	eq(sim.escape.stage, 2, "進入第二階段，進度未重置")
	check(run_until(sim, func(): return sim.escape.status == EscapeService.STATUS_WAITING, 70), "第二階段完成")
	sim.submit({"type": "portal_next_stage", "player_id": 2})
	eq(sim.events.count("portal_revealed"), 1, "第三階段開始時公開位置")
	check(run_until(sim, func(): return sim.is_over(), 90), "第三階段完成")
	eq(sim.result()["winner"], "elves", "完工立即精靈勝")
	eq(sim.result()["reason"], "escaped", "逃離勝利")
	var tick := sim.tick
	sim.step()
	eq(sim.tick, tick, "勝負鎖定後時間停止")
	eq(sim.submit({"type": "build", "player_id": 2, "def_id": "wall", "origin": [41, 13]})["reason"], "match_over", "鎖定後拒絕操作")


func test_time_limit_victory() -> void:
	var sim := new_sim()
	sim.tick = sim.match_svc.time_limit_ticks() - 1
	sim.step()
	eq(sim.result().get("reason"), "reinforcements", "25:00 有原始精靈存活 → 援軍勝")
	eq(sim.events.count("match_result_locked"), 1, "只鎖定一次")


func test_troll_victory_and_tie_rule() -> void:
	var sim := new_sim()
	for pid in [1, 2, 3]:
		sim.submit({"type": "debug_kill", "player_id": pid})
	sim.step()
	eq(sim.result().get("winner"), "trolls", "全部原始精靈死亡 → 巨魔勝")
	# 同 tick：傳送門完工 + 全員死亡 → 巨魔勝
	var sim2 := new_sim()
	sim2.escape.status = EscapeService.STATUS_COMPLETE
	for pid in [1, 2, 3]:
		sim2.unit_svc.kill_unit(sim2.unit_of(pid))
	sim2.match_svc.check_end_of_tick()
	eq(sim2.result().get("winner"), "trolls", "同 tick 以原始精靈是否存活為準")
	# 25:00 同 tick 全滅也是巨魔勝
	var sim3 := new_sim()
	sim3.tick = sim3.match_svc.time_limit_ticks()
	for pid in [1, 2, 3]:
		sim3.unit_svc.kill_unit(sim3.unit_of(pid))
	sim3.match_svc.check_end_of_tick()
	eq(sim3.result().get("winner"), "trolls", "時限當下已無原始精靈 → 巨魔勝")


func test_troll_kills_elf() -> void:
	var sim := new_sim()
	var t := spawn_troll(sim, Vector2i(33, 4))
	t.ai_enabled = true
	check(run_until(sim, func(): return not sim.players[1].alive_original, 20), "巨魔 AI 會追殺精靈")
	eq(sim.players[1].afterlife, "pending", "死後等待選擇陣營")


func test_afterlife_not_counted_and_soul_repair_needs_authorization() -> void:
	var sim := new_sim()
	var wall := add_building(sim, 3, "wall", Vector2i(33, 5), 1)
	wall.hp = 300
	sim.submit({"type": "debug_kill", "player_id": 1})
	sim.submit({"type": "debug_kill", "player_id": 2})
	check(sim.submit({"type": "death_choice", "player_id": 1, "choice": "soul"})["ok"], "選擇靈魂")
	check(sim.submit({"type": "death_choice", "player_id": 2, "choice": "minion"})["ok"], "選擇僕從")
	eq(sim.match_svc.alive_original_count(), 1, "靈魂與僕從都不算存活原始精靈")
	eq(sim.unit_of(2).team, "trolls", "僕從屬於巨魔方")
	teleport(sim.unit_of(1), Vector2i(34, 5))
	eq(sim.submit({"type": "repair", "player_id": 1, "instance_id": wall.instance_id})["reason"], "no_authorized_payer", "沒有授權不能修")
	sim.run_seconds(2)
	eq(wall.hp, 300, "未授權 HP 不變")
	sim.submit({"type": "set_soul_authorization", "player_id": 3, "enabled": true})
	set_res(sim, 3, 500, 500)
	check(sim.submit({"type": "repair", "player_id": 1, "instance_id": wall.instance_id})["ok"], "授權後可修")
	sim.run_seconds(2)
	check(wall.hp > 300, "靈魂修復生效")
	check(sim.players[3].gold < 500, "由授權的存活精靈付費")
	sim.submit({"type": "set_soul_authorization", "player_id": 3, "enabled": false})
	var hp := wall.hp
	sim.run_seconds(2)
	eq(wall.hp, hp, "撤銷授權後停止回血")
	eq(sim.submit({"type": "death_choice", "player_id": 1, "choice": "minion"})["reason"], "no_pending_choice", "只能選一次")


func test_troll_must_break_walls_to_enter() -> void:
	var sim := new_sim()
	var w1 := add_building(sim, 1, "wall", Vector2i(35, 9), 1)
	var w2 := add_building(sim, 1, "wall", Vector2i(36, 9), 1)
	var t := spawn_troll(sim, Vector2i(35, 14))
	t.ai_enabled = true
	check(run_until(sim, func(): return sim.events.count("building_damaged") > 0, 15), "巨魔先打入口城牆")
	for e in sim.events.find_all("building_damaged"):
		check(e["data"]["instance_id"] in [w1.instance_id, w2.instance_id], "被打的是擋路的城牆")
	check(t.cell().y >= 10, "牆完整時巨魔進不了基地")
	check(run_until(sim, func(): return not sim.players[1].alive_original, 60), "破牆後追殺精靈")
