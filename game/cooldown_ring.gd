extends Control
## 冷卻轉圈圖示：remaining = 剩餘比例（0 = 可用）。active = 正在作用中（例如修復進行中）。

var remaining := 0.0
var active := false


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(rem: float, is_active: bool) -> void:
	if absf(rem - remaining) > 0.001 or is_active != active:
		remaining = clampf(rem, 0.0, 1.0)
		active = is_active
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 3.0
	draw_circle(c, r, Color(0, 0, 0, 0.35))
	if remaining <= 0.0:
		draw_arc(c, r, 0, TAU, 40, Color("#5fd36b"), 3.0)
	else:
		# 已冷卻的部分亮、剩下的部分暗，從 12 點方向順時針轉
		var done := 1.0 - remaining
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU * done, 40, Color("#f0c020"), 3.0)
		draw_arc(c, r, -PI / 2 + TAU * done, -PI / 2 + TAU, 40, Color(1, 1, 1, 0.15), 3.0)
	if active:
		draw_circle(c, r * 0.45, Color("#4fd0ff"))
