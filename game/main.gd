extends Node
## 手機原型畫面：持有 MatchSim、把觸控轉成指令、顯示 HUD。
## 這裡不做任何扣款或勝負判定，只呼叫 sim.submit()。

const CELL := 32.0
const SPEEDS := [1.0, 4.0, 10.0]

const REASONS := {
	"insufficient_resources": "資源不足", "occupied": "位置已有建築", "blocked_terrain": "不可施工地形",
	"spawn_area": "出生區不可建造", "out_of_bounds": "超出地圖", "limit_reached": "已達數量上限",
	"requirement": "缺少前置", "unit_in_the_way": "有單位站在那裡", "builder_cannot_reach": "精靈走不到那裡",
	"not_living_elf": "只有存活的原始精靈可以做", "match_over": "對局已結束", "busy": "正在施工或升級",
	"max_level": "已是最高等級", "not_owner": "不是你的建築", "time_locked": "星界潮汐尚未開放",
	"zone_not_sealed": "保護區入口尚未用城牆封住", "outside_portal_zone": "只能建在藍色保護區內",
	"portal_exists": "全隊只能有一座傳送門", "initiator_cannot_reach": "你走不到傳送門旁",
	"not_waiting_for_payment": "目前不需要付款", "target_not_attackable": "這個目標不能被攻擊",
	"no_authorized_payer": "沒有存活精靈授權付費", "not_repairable": "不需要或不能修繕",
	"cancel_job_first": "請先取消施工", "nothing_to_cancel": "沒有進行中的施工", "no_pending_choice": "沒有待選擇",
	"invalid_destination": "不能走到那裡", "no_unit": "沒有可操控的單位", "both_must_be_living_elves": "雙方都要是存活精靈",
	"not_a_troll_unit": "需要操控巨魔方單位", "no_job_here": "這裡沒有你的工地", "payer_dead": "付款人已死亡",
	"full": "已修滿", "target_gone": "目標已消失",
}

var defs: DefinitionDB
var sim: MatchSim
var view_pid := 1
var speed_idx := 0
var paused := false
var acc := 0.0

var build_def := ""
var preview_origin := Vector2i(-99, -99)
var preview_result := {}
var selected_bid := -1

var world: Node2D
var map_view: Node2D
var camera: Camera2D

# 拖曳 / 點擊判斷
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false

# HUD
var ui := {}
var _refresh_timer := 0.0
var _msg_timer := 0.0


func _ready() -> void:
	defs = DefinitionDB.load_default()
	if not defs.is_valid():
		push_error("數值表錯誤：" + str(defs.errors))
	world = Node2D.new()
	add_child(world)
	map_view = Node2D.new()
	map_view.set_script(load("res://game/map_view.gd"))
	map_view.main = self
	world.add_child(map_view)
	camera = Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	_build_hud()
	_new_match()


func _new_match() -> void:
	sim = MatchSim.create(defs, 3)
	sim.events.event_emitted.connect(_on_event)
	view_pid = 1
	build_def = ""
	selected_bid = -1
	ui["result_panel"].visible = false
	_center_camera()
	_refresh_hud()


func _process(delta: float) -> void:
	if not paused and not sim.is_over():
		acc += delta * SPEEDS[speed_idx] * sim.tick_rate
		var n := 0
		while acc >= 1.0 and n < 60:
			sim.step()
			acc -= 1.0
			n += 1
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.15
		_refresh_hud()
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			ui["msg"].text = ""


# ---------- 視角 / 小工具 ----------

func view_team() -> String:
	return sim.players[view_pid].team()


func player_color(pid: int) -> Color:
	match pid:
		1: return Color("#3a7bd5")
		2: return Color("#9b59b6")
		3: return Color("#16a085")
	return Color("#c0392b")


func short_name(def_id: String) -> String:
	return {"elf_house": "屋", "lumber_grove": "林", "craft_hall": "廳", "wall": "牆", "arrow_tower": "箭",
		"frost_tower": "冰", "watch_tower": "瞭", "repair_post": "修", "escape_portal": "門"}.get(def_id, "?")


func reason_text(r: Dictionary) -> String:
	var t: String = REASONS.get(str(r.get("reason", "")), str(r.get("reason", "")))
	if r.has("detail"):
		t += "：" + str(r["detail"])
	return t


func say(text: String) -> void:
	ui["msg"].text = text
	_msg_timer = 3.0


func _submit(cmd: Dictionary) -> Dictionary:
	cmd["player_id"] = view_pid
	var r := sim.submit(cmd)
	if not r.get("ok", false):
		say("✗ " + reason_text(r))
	return r


func _center_camera() -> void:
	var u: UnitState = sim.unit_of(view_pid)
	if u:
		camera.position = u.pos * CELL


func _fmt_time(sec: float) -> String:
	var s := int(sec)
	return "%02d:%02d" % [s / 60, s % 60]


# ---------- 輸入 ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_pos = mb.position
			else:
				if _pressed and not _dragging:
					_on_tap(world.get_global_mouse_position())
				_pressed = false
				_dragging = false
	elif event is InputEventMouseMotion and _pressed:
		var mm := event as InputEventMouseMotion
		if not _dragging and mm.position.distance_to(_press_pos) > 14.0:
			_dragging = true
		if _dragging:
			camera.position -= mm.relative / camera.zoom.x
	elif event is InputEventMagnifyGesture:
		_zoom((event as InputEventMagnifyGesture).factor)


func _zoom(f: float) -> void:
	var z := clampf(camera.zoom.x * f, 0.35, 2.5)
	camera.zoom = Vector2(z, z)


func _on_tap(world_pos: Vector2) -> void:
	if sim.is_over():
		return
	var cell := Vector2i(int(floor(world_pos.x / CELL)), int(floor(world_pos.y / CELL)))
	var cellf := world_pos / CELL
	if build_def != "":
		var d: BuildingDefinition = defs.get_def(build_def)
		var origin := cell - (d.footprint - Vector2i.ONE) / 2
		if origin == preview_origin and preview_result.get("ok", false):
			_confirm_build()
		else:
			preview_origin = origin
			_update_preview()
		return
	var team := view_team()
	var inst := sim.building_at(cell)
	if team == "trolls":
		var target := _unit_near(cellf, "elves")
		if target:
			_submit({"type": "attack", "target_kind": "unit", "target_id": target.id})
			return
		if inst:
			selected_bid = inst.instance_id
			var r := _submit({"type": "attack", "target_kind": "building", "target_id": inst.instance_id})
			if r.get("ok", false):
				say("攻擊 %s" % defs.get_def(inst.def_id).display_name)
			return
		selected_bid = -1
		_submit({"type": "move", "cell": [cell.x, cell.y]})
		return
	if inst:
		selected_bid = inst.instance_id
		_refresh_hud()
		return
	selected_bid = -1
	_submit({"type": "move", "cell": [cell.x, cell.y]})


func _unit_near(p: Vector2, team: String) -> UnitState:
	var best: UnitState = null
	var bd := 0.8
	for u in sim.units.values():
		var unit: UnitState = u
		if unit.alive and unit.spawned and unit.team == team and unit.kind != UnitState.KIND_SOUL:
			var d := unit.pos.distance_to(p)
			if d < bd and sim.visibility.is_visible_to(view_team(), unit.pos):
				bd = d
				best = unit
	return best


func _update_preview() -> void:
	if build_def == "escape_portal":
		preview_result = sim.escape.validate_start(view_pid, preview_origin)
	else:
		preview_result = sim.building_svc.validate_place(view_pid, build_def, preview_origin)
	if preview_result.get("ok", false):
		say("位置可用：再點一次同一格或按「確認放置」")
	else:
		say("✗ " + reason_text(preview_result))


func _confirm_build() -> void:
	if build_def == "" or preview_origin.x < -50:
		return
	var r: Dictionary
	if build_def == "escape_portal":
		r = _submit({"type": "portal_start", "origin": [preview_origin.x, preview_origin.y]})
	else:
		r = _submit({"type": "build", "def_id": build_def, "origin": [preview_origin.x, preview_origin.y]})
	if r.get("ok", false):
		say("開始建造 %s" % defs.get_def(build_def).display_name)
		# 城牆常需要連續放：保持在建造模式
		if build_def != "wall":
			build_def = ""
		preview_origin = Vector2i(-99, -99)
		preview_result = {}
	_refresh_hud()


func _on_event(event_name: String, data: Dictionary) -> void:
	match event_name:
		"elf_died":
			if data["player_id"] == view_pid:
				say("你被巨魔擊殺了！請選擇陣營")
			else:
				say("精靈 %d 被擊殺" % data["player_id"])
		"troll_spawned":
			say("巨魔出現了！")
		"portal_alert_trolls":
			if view_team() == "trolls":
				say("⚠ 有精靈正在啟動傳送門！")
		"building_destroyed":
			var d: BuildingDefinition = defs.get_def(data["def_id"])
			if data["owner"] == view_pid:
				say("你的%s被摧毀了" % d.display_name)
		"match_result_locked":
			_show_result(data)


# ---------- HUD 建立 ----------

func _btn(text: String, cb: Callable, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func _label(parent: Node, size: int = 16) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _section(parent: Node, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var t := _label(box, 17)
	t.text = title
	t.add_theme_color_override("font_color", Color("#ffd479"))
	return box


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.14, 0.96)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(6)
	return sb


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# 上方列
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 56)
	top.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	top.add_child(hb)
	ui["time"] = _label(hb, 22)
	ui["time"].custom_minimum_size = Vector2(150, 0)
	ui["pbtns"] = []
	for pid in [1, 2, 3, MatchSim.TROLL_PLAYER_ID]:
		var b := _btn("", _select_player.bind(pid), hb)
		b.custom_minimum_size = Vector2(92, 44)
		b.toggle_mode = true
		ui["pbtns"].append(b)
	ui["res"] = _label(hb, 20)
	ui["res"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui["speed"] = _btn("x1", _cycle_speed, hb)
	ui["pause"] = _btn("暫停", _toggle_pause, hb)
	_btn("－", _zoom.bind(1.0 / 1.25), hb).custom_minimum_size = Vector2(44, 44)
	_btn("＋", _zoom.bind(1.25), hb).custom_minimum_size = Vector2(44, 44)
	_btn("找我", _center_camera, hb)

	# 右側面板
	var side := PanelContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.0
	side.anchor_bottom = 1.0
	side.offset_left = -360
	side.offset_top = 60
	side.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	# 建造
	var sb := _section(col, "建造")
	ui["build_sec"] = sb
	var grid := GridContainer.new()
	grid.columns = 2
	sb.add_child(grid)
	ui["build_btns"] = {}
	for id in defs.building_order:
		if id == "escape_portal":
			continue
		var b := _btn("", _enter_build.bind(id), grid)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(160, 52)
		b.add_theme_font_size_override("font_size", 13)
		ui["build_btns"][id] = b
	var bm := HBoxContainer.new()
	sb.add_child(bm)
	ui["build_mode"] = bm
	ui["build_mode_lbl"] = _label(bm, 14)
	ui["build_mode_lbl"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn("確認放置", _confirm_build, bm)
	_btn("取消", _exit_build, bm)

	# 選取的建築
	var sel := _section(col, "選取的建築")
	ui["sel_sec"] = sel
	ui["sel_info"] = _label(sel, 15)
	var sel_btns := GridContainer.new()
	sel_btns.columns = 2
	sel.add_child(sel_btns)
	ui["b_upgrade"] = _btn("升級", _act.bind("upgrade"), sel_btns)
	ui["b_resume"] = _btn("續建", _act.bind("resume_build"), sel_btns)
	ui["b_cancel"] = _btn("取消施工", _act.bind("cancel"), sel_btns)
	ui["b_repair"] = _btn("修繕", _act.bind("repair"), sel_btns)
	ui["b_demolish"] = _btn("拆除", _act.bind("demolish"), sel_btns)
	ui["b_attack"] = _btn("攻擊", _act.bind("attack"), sel_btns)
	for k in ["b_upgrade", "b_resume", "b_cancel", "b_repair", "b_demolish", "b_attack"]:
		ui[k].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui[k].add_theme_font_size_override("font_size", 13)

	# 傳送門
	var ps := _section(col, "星界傳送門")
	ui["portal_info"] = _label(ps, 15)
	ui["b_portal_place"] = _btn("選擇位置建造傳送門", _enter_build.bind("escape_portal"), ps)
	ui["b_portal_work"] = _btn("前往傳送門施工", func(): _submit({"type": "portal_work"}), ps)
	ui["b_portal_next"] = _btn("支付並開始下一階段", func(): _submit({"type": "portal_next_stage"}), ps)

	# 團隊
	var ts := _section(col, "團隊")
	ui["team_sec"] = ts
	ui["team_info"] = _label(ts, 14)
	ui["donate"] = {}
	for pid in [1, 2, 3]:
		var row := HBoxContainer.new()
		ts.add_child(row)
		var l := _label(row, 14)
		l.text = "給精靈 %d" % pid
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_btn("+100金", _donate.bind(pid, 100, 0), row)
		_btn("+30木", _donate.bind(pid, 0, 30), row)
		ui["donate"][pid] = row
	var auth := CheckButton.new()
	auth.text = "允許靈魂修復花我的錢"
	auth.focus_mode = Control.FOCUS_NONE
	auth.toggled.connect(func(on): _submit({"type": "set_soul_authorization", "enabled": on}))
	ts.add_child(auth)
	ui["auth"] = auth

	# 巨魔
	var trs := _section(col, "巨魔")
	ui["troll_sec"] = trs
	ui["troll_info"] = _label(trs, 14)
	var ai := CheckButton.new()
	ai.text = "自動 AI（測試用）"
	ai.focus_mode = Control.FOCUS_NONE
	ai.toggled.connect(func(on): _submit({"type": "set_troll_ai", "enabled": on}))
	trs.add_child(ai)
	ui["ai"] = ai

	# 測試工具
	var dbg := _section(col, "測試工具")
	var drow := GridContainer.new()
	drow.columns = 2
	dbg.add_child(drow)
	_btn("+1000金 +300木", func(): _submit({"type": "debug_grant", "gold": 1000, "wood": 300}), drow)
	_btn("跳到 12:00", func(): sim.submit({"type": "debug_set_time", "sec": maxf(sim.now_sec(), 720.0)}), drow)
	_btn("跳到 24:50", func(): sim.submit({"type": "debug_set_time", "sec": maxf(sim.now_sec(), 1490.0)}), drow)
	_btn("巨魔立刻出場", _spawn_troll_now, drow)
	_btn("重新開局", _new_match, drow)

	# 訊息
	var msg := Label.new()
	msg.add_theme_font_size_override("font_size", 20)
	msg.add_theme_color_override("font_color", Color.WHITE)
	msg.add_theme_color_override("font_outline_color", Color.BLACK)
	msg.add_theme_constant_override("outline_size", 6)
	msg.anchor_top = 1.0
	msg.anchor_bottom = 1.0
	msg.offset_left = 16
	msg.offset_top = -50
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(msg)
	ui["msg"] = msg

	# 死亡選擇
	var dp := PanelContainer.new()
	dp.set_anchors_preset(Control.PRESET_CENTER)
	dp.custom_minimum_size = Vector2(460, 0)
	dp.offset_left = -230
	dp.offset_top = -110
	dp.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(dp)
	var dv := VBoxContainer.new()
	dp.add_child(dv)
	var dl := _label(dv, 20)
	dl.text = "你被擊殺了。選擇繼續參戰的陣營："
	_btn("精靈方靈魂（修復／協助攻擊／控制）", func(): _submit({"type": "death_choice", "choice": "soul"}), dv)
	_btn("巨魔方僕從（較弱，可攻擊建築）", func(): _submit({"type": "death_choice", "choice": "minion"}), dv)
	ui["death_panel"] = dp

	# 結果
	var rp := PanelContainer.new()
	rp.set_anchors_preset(Control.PRESET_CENTER)
	rp.custom_minimum_size = Vector2(520, 0)
	rp.offset_left = -260
	rp.offset_top = -120
	rp.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(rp)
	var rv := VBoxContainer.new()
	rp.add_child(rv)
	ui["result_lbl"] = _label(rv, 26)
	ui["result_lbl"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn("再來一局", _new_match, rv)
	rp.visible = false
	ui["result_panel"] = rp


# ---------- HUD 動作 ----------

func _select_player(pid: int) -> void:
	view_pid = pid
	build_def = ""
	selected_bid = -1
	_center_camera()
	_refresh_hud()


func _cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()


func _toggle_pause() -> void:
	paused = not paused


func _enter_build(def_id: String) -> void:
	build_def = def_id
	selected_bid = -1
	preview_origin = Vector2i(-99, -99)
	preview_result = {}
	say("點地圖選擇%s的位置" % defs.get_def(def_id).display_name)
	_refresh_hud()


func _exit_build() -> void:
	build_def = ""
	preview_origin = Vector2i(-99, -99)
	_refresh_hud()


func _act(kind: String) -> void:
	if selected_bid == -1:
		return
	match kind:
		"attack":
			_submit({"type": "attack", "target_kind": "building", "target_id": selected_bid})
		_:
			var r := _submit({"type": kind, "instance_id": selected_bid})
			if r.get("ok", false) and kind == "demolish":
				selected_bid = -1
	_refresh_hud()


func _donate(to_pid: int, g: int, w: int) -> void:
	var r := _submit({"type": "donate", "to_player_id": to_pid, "gold": g, "wood": w})
	if r.get("ok", false):
		say("已贈送給精靈 %d" % to_pid)


func _spawn_troll_now() -> void:
	sim.troll_spawn_tick = sim.tick + 1


func _show_result(r: Dictionary) -> void:
	var text := ""
	match str(r["reason"]):
		"escaped": text = "精靈勝利！\n星界傳送門完成，精靈成功逃離。"
		"reinforcements": text = "精靈勝利！\n撐過 25:00，精靈援軍擊退了巨魔。"
		"all_elves_eliminated": text = "巨魔勝利！\n所有原始精靈都被消滅了。"
	ui["result_lbl"].text = text + "\n（%s）" % _fmt_time(r["time_sec"])
	ui["result_panel"].visible = true


# ---------- HUD 更新 ----------

## 建造按鈕要顯示的阻擋原因（不看位置）。
func _build_block_reason(pid: int, def_id: String) -> String:
	var p: PlayerAccount = sim.players[pid]
	if not p.alive_original:
		return "已陣亡"
	var d: BuildingDefinition = defs.get_def(def_id)
	if d.max_per_player > 0 and sim.building_svc.count_owned(pid, def_id) >= d.max_per_player:
		return "已達上限 %d" % d.max_per_player
	var miss: String = sim.building_svc.missing_requirement(pid, d.level(1)["requires"])
	if miss != "":
		return miss
	var lv := d.level(1)
	if not sim.economy.can_afford(pid, lv["cost_g"], lv["cost_w"]):
		return "資源不足"
	return ""


func _refresh_hud() -> void:
	if sim == null:
		return
	var p: PlayerAccount = sim.players[view_pid]
	var team := p.team()
	var is_elf_alive := p.alive_original
	ui["time"].text = "%s / %s" % [_fmt_time(sim.now_sec()), _fmt_time(float(sim.cfg["match_time_limit_sec"]))]
	var ids := [1, 2, 3, MatchSim.TROLL_PLAYER_ID]
	for i in ids.size():
		var pp: PlayerAccount = sim.players[ids[i]]
		var b: Button = ui["pbtns"][i]
		var suffix := ""
		match pp.afterlife:
			"pending": suffix = "†"
			"soul": suffix = "(魂)"
			"minion": suffix = "(僕)"
		b.text = ("巨魔" if pp.role == "troll" else "精靈%d" % pp.id) + suffix
		b.button_pressed = ids[i] == view_pid
	if p.role == "troll" or p.afterlife == "minion":
		ui["res"].text = "戰鬥收益 %d" % p.troll_gold
	else:
		ui["res"].text = "金 %d   木 %d" % [p.gold, p.wood]
	ui["speed"].text = "x%d" % int(SPEEDS[speed_idx])
	ui["pause"].text = "繼續" if paused else "暫停"
	ui["death_panel"].visible = p.afterlife == "pending" and not sim.is_over()

	# 建造
	ui["build_sec"].visible = is_elf_alive
	if is_elf_alive:
		for id in ui["build_btns"]:
			var d: BuildingDefinition = defs.get_def(id)
			var lv := d.level(1)
			var block := _build_block_reason(view_pid, id)
			var b: Button = ui["build_btns"][id]
			b.text = "%s  %dG/%dW\n%s" % [d.display_name, lv["cost_g"], lv["cost_w"], block if block != "" else "%d 秒" % int(lv["time_sec"])]
			b.modulate = Color(1, 1, 1, 0.55) if block != "" else Color.WHITE
			b.disabled = block != ""
	ui["build_mode"].visible = build_def != ""
	if build_def != "":
		ui["build_mode_lbl"].text = "放置：" + defs.get_def(build_def).display_name
		if preview_origin.x > -50:
			_update_preview_silent()

	# 選取
	var inst: BuildingInstance = sim.buildings.get(selected_bid)
	ui["sel_sec"].visible = inst != null
	if inst:
		_refresh_selection(inst, p)

	# 傳送門
	_refresh_portal(p)

	# 團隊
	ui["team_sec"].visible = team == "elves"
	var lines: Array[String] = []
	for pid in [1, 2, 3]:
		var pp: PlayerAccount = sim.players[pid]
		var state: String = "存活" if pp.alive_original else {"pending": "陣亡", "soul": "靈魂", "minion": "僕從"}.get(pp.afterlife, "")
		lines.append("精靈%d：%s  金%d 木%d%s" % [pid, state, pp.gold, pp.wood, "  ✓授權靈魂" if pp.authorize_soul_repair else ""])
	var soul_u: UnitState = sim.unit_of(view_pid)
	if p.afterlife == "soul" and soul_u:
		lines.append("靈魂能量 %d / %d" % [int(soul_u.energy), int(soul_u.energy_max)])
	ui["team_info"].text = "\n".join(lines)
	for pid in ui["donate"]:
		ui["donate"][pid].visible = is_elf_alive and pid != view_pid and sim.players[pid].alive_original
	ui["auth"].visible = is_elf_alive
	ui["auth"].set_pressed_no_signal(p.authorize_soul_repair)

	# 巨魔
	ui["troll_sec"].visible = team == "trolls"
	var tu: UnitState = sim.unit_of(view_pid)
	if team == "trolls" and tu:
		var t := "HP %d / %d" % [tu.hp, tu.max_hp] if tu.alive else "等待重生"
		if not tu.spawned:
			t = "%d 秒後出場" % ceili(float(sim.troll_spawn_tick - sim.tick) / sim.tick_rate)
		if sim.escape.trolls_alerted:
			t += "\n⚠ 有精靈正在啟動傳送門"
		if sim.escape.revealed:
			t += "\n傳送門位置已公開"
		t += "\n點精靈＝攻擊；點建築＝攻擊；點空地＝移動"
		ui["troll_info"].text = t
		ui["ai"].set_pressed_no_signal(tu.ai_enabled)


func _update_preview_silent() -> void:
	if build_def == "escape_portal":
		preview_result = sim.escape.validate_start(view_pid, preview_origin)
	else:
		preview_result = sim.building_svc.validate_place(view_pid, build_def, preview_origin)


func _refresh_selection(inst: BuildingInstance, p: PlayerAccount) -> void:
	var d: BuildingDefinition = defs.get_def(inst.def_id)
	var lines: Array[String] = []
	var owner_name := "精靈%d" % inst.owner_player_id
	lines.append("%s（%s）" % [d.display_name, owner_name])
	var mine := inst.owner_player_id == view_pid and p.alive_original
	if d.is_portal():
		lines.append("團隊勝利建築，不可被攻擊、沒有 HP")
	else:
		var lv_name: String = d.level(inst.level)["name"] if inst.level > 0 else "施工中"
		lines.append("等級 %d %s   HP %d / %d" % [inst.level, lv_name, inst.hp, inst.max_hp])
		if inst.has_job():
			var present: bool = sim.building_svc.is_builder_present(inst)
			lines.append("%s %d%%（剩 %.0f 秒）%s" % ["建造" if inst.state == BuildingInstance.ST_CONSTRUCTING else "升級到 Lv%d" % inst.job_target_level,
				int(100.0 * inst.job_progress_ticks / maxi(1, inst.job_required_ticks)),
				float(inst.remaining_job_ticks()) / sim.tick_rate, "" if present else "  ⏸ 建造者不在旁邊"])
		if inst.level > 0:
			var lv := d.level(inst.level)
			if lv["gold_per_sec"] > 0: lines.append("產量 %d 金/秒" % lv["gold_per_sec"])
			if lv["wood_per_sec"] > 0: lines.append("產量 %d 木/秒" % lv["wood_per_sec"])
			if not lv["attack"].is_empty(): lines.append("傷害 %d／%.1f 秒，射程 %d" % [lv["attack"]["damage"], lv["attack"]["interval_ticks"] / 10.0, int(lv["attack"]["range"])])
			if not lv["slow"].is_empty(): lines.append("緩速 %d%%，射程 %d" % [lv["slow"]["percent"], int(lv["slow"]["range"])])
	ui["sel_info"].text = "\n".join(lines)
	# 按鈕
	var up := sim.building_svc.validate_upgrade(view_pid, inst.instance_id)
	var can_show_up := mine and not d.is_portal() and inst.level < d.max_level() and inst.state == BuildingInstance.ST_ACTIVE
	ui["b_upgrade"].visible = can_show_up
	if can_show_up:
		var nxt := d.level(inst.level + 1)
		ui["b_upgrade"].text = "升級 Lv%d %dG/%dW%s" % [inst.level + 1, nxt["cost_g"], nxt["cost_w"], "" if up["ok"] else "\n" + reason_text(up)]
		ui["b_upgrade"].disabled = not up["ok"]
	ui["b_resume"].visible = mine and inst.has_job() and p.job_instance_id != inst.instance_id
	ui["b_cancel"].visible = mine and inst.has_job()
	if inst.has_job():
		var refund: Array = sim.building_svc.refund_for_cancel(inst, int(sim.cfg["construction"]["cancel_refund_percent"]))
		ui["b_cancel"].text = "取消（退 %dG/%dW）" % [refund[0], refund[1]]
	var u: UnitState = sim.unit_of(view_pid)
	var can_repair_unit := u != null and u.alive and (u.kind == UnitState.KIND_ELF or u.kind == UnitState.KIND_SOUL)
	ui["b_repair"].visible = can_repair_unit and sim.repair.can_be_repaired(inst)
	if ui["b_repair"].visible:
		var full_g := inst.total_paid_g * int(sim.cfg["repair"]["cost_ratio_percent"]) * (inst.max_hp - inst.hp) / (100 * inst.max_hp)
		var full_w := inst.total_paid_w * int(sim.cfg["repair"]["cost_ratio_percent"]) * (inst.max_hp - inst.hp) / (100 * inst.max_hp)
		ui["b_repair"].text = "修繕（修滿約 %dG/%dW）" % [full_g, full_w]
	ui["b_demolish"].visible = mine and inst.state == BuildingInstance.ST_ACTIVE and not d.is_portal()
	ui["b_attack"].visible = p.team() == "trolls" and sim.combat.is_attackable_building(inst)


func _refresh_portal(p: PlayerAccount) -> void:
	var st := sim.escape.ui_status(view_pid)
	var d: BuildingDefinition = defs.get_def("escape_portal")
	var lines: Array[String] = []
	var is_elf_alive := p.alive_original
	if p.team() == "trolls":
		if sim.escape.revealed:
			lines.append("第 %d 階段，位置已公開" % sim.escape.stage)
		elif sim.escape.trolls_alerted:
			lines.append("有精靈正在啟動傳送門（位置未知）")
		else:
			lines.append("沒有情報")
		ui["portal_info"].text = "\n".join(lines)
		for k in ["b_portal_place", "b_portal_work", "b_portal_next"]:
			ui[k].visible = false
		return
	if not st["exists"]:
		lines.append("總成本 6500G/1300W，三階段共 190 秒")
		if st["time_locked_sec"] > 0:
			lines.append("⏳ %s 後開放（12:00）" % _fmt_time(st["time_locked_sec"]))
		if st["missing"] != "":
			lines.append("✗ %s" % st["missing"])
		lines.append("第一階段 %dG/%dW %s" % [st["next_cost_g"], st["next_cost_w"], "✓" if st["can_afford_next"] else "✗ 資源不足"])
		lines.append("只能建在藍色保護區，入口需先用城牆封住")
	else:
		var stage_def: Dictionary = d.stages[maxi(0, st["stage"] - 1)]
		lines.append("階段 %d / %d：%s" % [st["stage"], st["stages"], stage_def["name"]])
		match st["status"]:
			EscapeService.STATUS_BUILDING:
				lines.append(("▶ 施工中（%d 人）" % st["builders"]) if st["working"] else "⏸ 暫停：3 格內沒有存活精靈")
				lines.append("剩餘約 %.0f 秒" % st["remaining_sec"])
			EscapeService.STATUS_WAITING:
				lines.append("本階段完成，等待支付下一階段 %dG/%dW %s" % [st["next_cost_g"], st["next_cost_w"], "✓" if st["can_afford_next"] else "✗ 資源不足"])
			EscapeService.STATUS_COMPLETE:
				lines.append("完成！")
	ui["portal_info"].text = "\n".join(lines)
	ui["b_portal_place"].visible = is_elf_alive and not st["exists"]
	ui["b_portal_place"].disabled = st.get("time_locked_sec", 0) > 0 or st.get("missing", "") != ""
	ui["b_portal_work"].visible = is_elf_alive and st["exists"] and st["status"] != EscapeService.STATUS_COMPLETE
	ui["b_portal_next"].visible = is_elf_alive and st["status"] == EscapeService.STATUS_WAITING
