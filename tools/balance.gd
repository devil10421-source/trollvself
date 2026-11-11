extends SceneTree
## 開發用：三個電腦精靈對巨魔 AI 跑一整局，印出時間軸，用來粗調數值。
##   godot --headless --path . --script res://tools/balance.gd

func _initialize() -> void:
	var defs := DefinitionDB.load_default()
	var sim := MatchSim.create(defs, 3)
	var bot := ElfBot.new(sim, [1, 2, 3])
	var tr: UnitState = sim.unit_of(MatchSim.TROLL_PLAYER_ID)
	var t0 := Time.get_ticks_msec()
	var seen := 0
	while not sim.is_over():
		sim.step()
		bot.tick()
		while seen < sim.events.log.size():
			var e: Dictionary = sim.events.log[seen]
			seen += 1
			if e["name"] in ["elf_died", "gate_broken", "troll_level_up", "unit_died", "house_ejected"]:
				print("  %s  %s %s" % [_t(e["tick"] / 10.0), e["name"], str(e["data"])])
		if sim.tick % 1800 == 0:
			var line := "%s 巨魔 Lv%d HP %d/%d |" % [_t(sim.now_sec()), tr.level, tr.hp, tr.max_hp]
			for pid in [1, 2, 3]:
				var p: PlayerAccount = sim.players[pid]
				var job: BuildingInstance = sim.buildings.get(p.job_instance_id)
				line += " 精靈%d:%s 屋%d 林%d 廳%d 塔%d 金%d 木%d%s |" % [pid, "活" if p.alive_original else "亡", sim.house.house_level(pid), sim.building_svc.owner_level(pid, "lumber_grove"), sim.building_svc.owner_level(pid, "craft_hall"), sim.building_svc.count_owned(pid, "arrow_tower"), p.gold, p.wood, (" 工:%s@%s %d/%d" % [job.def_id, str(job.origin), job.job_progress_ticks, job.job_required_ticks]) if job else ""]
			print(line)
	print("結果：", sim.result(), "  巨魔 Lv", tr.level, "  耗時 ", Time.get_ticks_msec() - t0, " ms")
	quit()


func _t(sec: float) -> String:
	return "%02d:%02d" % [int(sec) / 60, int(sec) % 60]
