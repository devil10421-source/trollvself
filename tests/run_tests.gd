extends SceneTree
## 無畫面執行全部測試：
##   godot --headless --path . --script res://tests/run_tests.gd

const SUITES := [
	"res://tests/test_buildings.gd",
	"res://tests/test_portal_and_match.gd",
]


func _initialize() -> void:
	var total := 0
	var failed := 0
	for path in SUITES:
		var script: GDScript = load(path)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var t = script.new()
			t.current = name
			var start := Time.get_ticks_msec()
			t.call(name)
			total += 1
			var ms := Time.get_ticks_msec() - start
			if t.failures.is_empty():
				print("  通過  %s  (%d ms)" % [name, ms])
			else:
				failed += 1
				print("  失敗  %s" % name)
				for f in t.failures:
					print("        - " + f)
	print("\n共 %d 項，通過 %d，失敗 %d" % [total, total - failed, failed])
	quit(1 if failed > 0 else 0)
