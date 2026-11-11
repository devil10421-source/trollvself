extends SceneTree
## 開發用：開啟主畫面、跑一段劇本、存截圖。
##   xvfb-run godot --path . --rendering-method gl_compatibility --script res://tools/screenshot.gd -- out.png scenario

var main
var frames := 0
var out := "shot.png"
var scenario := "base"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	if args.size() > 1: scenario = args[1]
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		_setup()
	if frames == 30:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		quit()
	return false


func _setup() -> void:
	var sim: MatchSim = main.sim
	main.paused = true
	sim.players[1].gold = 3000
	sim.players[1].wood = 800
	if scenario == "base":
		sim.submit({"type": "build", "player_id": 1, "def_id": "elf_house", "origin": [31, 2]})
		sim.run_seconds(12)
		sim.submit({"type": "build", "player_id": 1, "def_id": "lumber_grove", "origin": [38, 2]})
		sim.run_seconds(14)
		sim.submit({"type": "build", "player_id": 1, "def_id": "wall", "origin": [35, 8]})
		sim.run_seconds(2)
		main.selected_bid = sim.grid.occupant(Vector2i(38, 2))
		main._enter_build("craft_hall")
		main.preview_origin = Vector2i(33, 5)
		main._update_preview()
		main.camera.position = Vector2(33, 7) * 32
	elif scenario == "portal":
		var t = load("res://tests/test_case.gd").new()
		t.ready_for_portal(sim, 1, Vector2i(31, 2), Vector2i(38, 6))
		t.seal_portal_zone(sim, 1)
		t.teleport(sim.unit_of(1), Vector2i(41, 13))
		t.teleport(sim.unit_of(2), Vector2i(41, 18))
		sim.submit({"type": "portal_start", "player_id": 1, "origin": [42, 14]})
		sim.run_seconds(20)
		var tr: UnitState = t.spawn_troll(sim, Vector2i(36, 15))
		tr.ai_enabled = true
		sim.run_seconds(4)
		main.selected_bid = sim.escape.portal_id
		main.camera.position = Vector2(38, 15) * 32
	elif scenario == "v07" or scenario == "v07troll":
		var t = load("res://tests/test_case.gd").new()
		var house: BuildingInstance = t.add_building(sim, 1, "elf_house", Vector2i(31, 2), 2)
		t.add_building(sim, 1, "lumber_grove", Vector2i(38, 2), 1)
		t.add_building(sim, 1, "craft_hall", Vector2i(31, 5), 1)
		var w: BuildingInstance = t.add_building(sim, 1, "arrow_tower", Vector2i(34, 7), 1)
		t.add_building(sim, 1, "watch_tower", Vector2i(37, 7), 1)
		t.put_inside(sim, 1, house)
		sim.step()
		var tr: UnitState = t.spawn_troll(sim, Vector2i(35, 11))
		sim.troll.add_xp(1600, "shot")
		sim.submit({"type": "attack", "player_id": MatchSim.TROLL_PLAYER_ID, "target_kind": "building", "target_id": sim.house.gate_of(1).instance_id})
		sim.submit({"type": "troll_skill", "player_id": MatchSim.TROLL_PLAYER_ID, "skill": "smash"})
		sim.run_seconds(8)
		sim.submit({"type": "house_repair", "player_id": 1})
		sim.run_seconds(1)
		main.selected_bid = sim.house.gate_of(1).instance_id
		main.camera.position = Vector2(35, 7) * 32
		if scenario == "v07troll":
			main.view_pid = MatchSim.TROLL_PLAYER_ID
		w.hp = w.hp
	main._refresh_hud()
