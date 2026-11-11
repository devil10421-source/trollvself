extends Node2D
## 戰爭迷霧 + 放置預覽 + 選取框（畫在所有東西上面）。

const CELL := 32.0
const C_FOG := Color(0.03, 0.05, 0.10, 0.52)

var main


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var sim: MatchSim = main.sim
	var g: TileGrid = sim.grid
	var arr: PackedByteArray = sim.visibility.visible[main.view_team()]
	if arr.size() == g.width * g.height:
		for y in g.height:
			var run := -1
			for x in g.width + 1:
				var dark := x < g.width and arr[y * g.width + x] == 0
				if dark and run == -1:
					run = x
				elif not dark and run != -1:
					draw_rect(Rect2(Vector2(run, y) * CELL, Vector2((x - run) * CELL, CELL)), C_FOG)
					run = -1
	# 放置預覽
	if main.build_def != "" and main.preview_origin.x > -50:
		var d: BuildingDefinition = sim.defs.get_def(main.build_def)
		var ok: bool = main.preview_result.get("ok", false)
		var col := Color(0.2, 0.95, 0.3, 0.45) if ok else Color(0.95, 0.2, 0.2, 0.45)
		var r := Rect2(Vector2(main.preview_origin) * CELL, Vector2(d.footprint) * CELL)
		draw_rect(r, col)
		draw_rect(r, col.lightened(0.5), false, 2.0)
	# 選取框
	var sel: BuildingInstance = sim.buildings.get(main.selected_bid)
	if sel:
		var r2 := Rect2(Vector2(sel.origin) * CELL, Vector2(sel.size) * CELL).grow(3)
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 160.0)
		draw_rect(r2, Color(0.4, 1.0, 0.4, pulse), false, 2.5)
