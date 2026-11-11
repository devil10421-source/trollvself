extends SceneTree
## 開發用：無畫面跑一整局（巨魔 AI 開、立刻出場），檢查沒有執行期錯誤。
##   godot --headless --path . --script res://tools/smoke.gd

func _initialize() -> void:
	var defs := DefinitionDB.load_default({"troll": {"spawn_delay_sec": 0}})
	var sim := MatchSim.create(defs, 3)
	for pid in [1, 2, 3]:
		sim.submit({"type": "debug_grant", "player_id": pid, "gold": 3000, "wood": 800})
	var spots := {1: [31, 2], 2: [31, 25], 3: [7, 2]}
	for pid in spots:
		sim.submit({"type": "build", "player_id": pid, "def_id": "elf_house", "origin": spots[pid]})
	var t0 := Time.get_ticks_msec()
	for sec in 1500:
		if sim.is_over():
			break
		if sec % 15 == 0:
			for pid in [1, 2, 3]:
				if sim.players[pid].alive_original:
					sim.submit({"type": "enter_house", "player_id": pid})
					sim.submit({"type": "house_repair", "player_id": pid})
				elif sim.players[pid].afterlife == "pending":
					sim.submit({"type": "death_choice", "player_id": pid, "choice": "soul" if pid != 2 else "minion"})
				else:
					sim.submit({"type": "soul_skill", "player_id": pid, "skill": "mark"})
		sim.run_seconds(1)
	var tr: UnitState = sim.unit_of(MatchSim.TROLL_PLAYER_ID)
	print("結果：", sim.result(), "  巨魔 Lv", tr.level, "  耗時 ", Time.get_ticks_msec() - t0, " ms")
	for e in ["gate_broken", "troll_level_up", "house_ejected", "troll_recalled", "elf_died"]:
		print("  ", e, " × ", sim.events.count(e))
	quit()
