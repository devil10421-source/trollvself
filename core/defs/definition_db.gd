class_name DefinitionDB
extends RefCounted
## 讀取並驗證 data/ 下的數值表。全遊戲只有這一份定義，畫面、經濟、修繕都從這裡讀。

const BUILDINGS_PATH := "res://data/buildings.json"
const CONFIG_PATH := "res://data/match_config.json"

var buildings := {}            # id -> BuildingDefinition
var building_order: Array[String] = []
var config := {}
var errors: Array[String] = []


static func load_default(config_overrides: Dictionary = {}) -> DefinitionDB:
	return load_from(BUILDINGS_PATH, CONFIG_PATH, config_overrides)


static func load_from(buildings_path: String, config_path: String, config_overrides: Dictionary = {}) -> DefinitionDB:
	var db := DefinitionDB.new()
	var b = _read_json(buildings_path, db.errors)
	var c = _read_json(config_path, db.errors)
	if b is Dictionary and c is Dictionary:
		db.config = c.duplicate(true)
		deep_merge(db.config, config_overrides)
		db._parse_buildings(b)
		db._validate_config()
	return db


static func _read_json(path: String, errs: Array[String]) -> Variant:
	if not FileAccess.file_exists(path):
		errs.append("找不到檔案 %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		errs.append("JSON 格式錯誤：%s" % path)
	return parsed


static func deep_merge(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if base.has(k) and base[k] is Dictionary and over[k] is Dictionary:
			deep_merge(base[k], over[k])
		else:
			base[k] = over[k]


func tick_rate() -> int:
	return int(config.get("tick_rate", 10))


func sec_to_ticks(sec: float) -> int:
	return int(round(sec * tick_rate()))


func get_def(id: String) -> BuildingDefinition:
	return buildings.get(id, null)


func is_valid() -> bool:
	return errors.is_empty()


func _parse_buildings(root: Dictionary) -> void:
	var list = root.get("buildings", [])
	if not list is Array:
		errors.append("buildings.json 缺少 buildings 陣列")
		return
	for raw in list:
		var d := BuildingDefinition.new()
		d.id = str(raw.get("id", ""))
		if d.id == "" or buildings.has(d.id):
			errors.append("建築 id 缺漏或重複：'%s'" % d.id)
			continue
		d.display_name = str(raw.get("name", d.id))
		d.category = str(raw.get("category", ""))
		var fp = raw.get("footprint", [1, 1])
		d.footprint = Vector2i(int(fp[0]), int(fp[1]))
		if d.footprint.x < 1 or d.footprint.y < 1:
			errors.append("%s 占地不合法" % d.id)
		d.max_per_player = int(raw.get("max_per_player", 0))
		d.max_per_team = int(raw.get("max_per_team", 0))
		d.targetable_by_enemies = bool(raw.get("targetable_by_enemies", true))
		d.damageable = bool(raw.get("damageable", true))
		d.color = Color.from_string(str(raw.get("color", "#ffffff")), Color.WHITE)
		d.requires = _parse_requires(raw.get("requires", []), d.id)
		var lv_n := 0
		for lv in raw.get("levels", []):
			lv_n += 1
			if int(lv.get("level", -1)) != lv_n:
				errors.append("%s 等級必須從 1 連續編號（第 %d 筆）" % [d.id, lv_n])
			var e := {
				"level": lv_n,
				"name": str(lv.get("name", "Lv%d" % lv_n)),
				"cost_g": _nonneg_int(lv.get("cost", {}).get("G", -1), "%s Lv%d 金幣成本" % [d.id, lv_n]),
				"cost_w": _nonneg_int(lv.get("cost", {}).get("W", -1), "%s Lv%d 木材成本" % [d.id, lv_n]),
				"time_ticks": maxi(1, sec_to_ticks(float(lv.get("time", 0)))),
				"time_sec": float(lv.get("time", 0)),
				"hp": _nonneg_int(lv.get("hp", -1), "%s Lv%d HP" % [d.id, lv_n]),
				"gold_per_sec": int(lv.get("gold_per_sec", 0)),
				"wood_per_sec": int(lv.get("wood_per_sec", 0)),
				"vision": float(lv.get("vision", config.get("building_default_vision", 4))),
				"requires": _parse_requires(lv.get("requires", []), d.id),
				"attack": {},
				"slow": {},
				"repair_aura": {},
			}
			if e["hp"] <= 0:
				errors.append("%s Lv%d HP 必須大於 0" % [d.id, lv_n])
			if lv.has("attack"):
				var a: Dictionary = lv["attack"]
				e["attack"] = {
					"damage": int(a.get("damage", 0)),
					"interval_ticks": maxi(1, sec_to_ticks(float(a.get("interval", 1.0)))),
					"range": float(a.get("range", 0)),
				}
			if lv.has("slow"):
				var s: Dictionary = lv["slow"]
				e["slow"] = {
					"percent": int(s.get("percent", 0)),
					"duration_ticks": sec_to_ticks(float(s.get("duration", 0))),
					"interval_ticks": maxi(1, sec_to_ticks(float(s.get("interval", 1.0)))),
					"range": float(s.get("range", 0)),
				}
			if lv.has("repair_aura"):
				var r: Dictionary = lv["repair_aura"]
				e["repair_aura"] = {
					"radius": float(r.get("radius", 0)),
					"speed_bonus_percent": int(r.get("speed_bonus_percent", 0)),
				}
			d.levels.append(e)
		var st_n := 0
		for st in raw.get("stages", []):
			st_n += 1
			d.stages.append({
				"stage": st_n,
				"name": str(st.get("name", "階段 %d" % st_n)),
				"cost_g": _nonneg_int(st.get("cost", {}).get("G", -1), "%s 階段%d 金幣" % [d.id, st_n]),
				"cost_w": _nonneg_int(st.get("cost", {}).get("W", -1), "%s 階段%d 木材" % [d.id, st_n]),
				"time_ticks": maxi(1, sec_to_ticks(float(st.get("time", 0)))),
				"time_sec": float(st.get("time", 0)),
				"reveal": str(st.get("reveal", "none")),
			})
		if d.levels.is_empty() and d.stages.is_empty():
			errors.append("%s 沒有任何等級或施工階段" % d.id)
		if d.is_portal() and (d.targetable_by_enemies or d.damageable):
			errors.append("V0.6：傳送門必須 targetable_by_enemies=false 且 damageable=false")
		buildings[d.id] = d
		building_order.append(d.id)
	# 前置建築必須存在
	for id in building_order:
		var d: BuildingDefinition = buildings[id]
		var all_reqs: Array = d.requires.duplicate()
		for lv in d.levels:
			all_reqs.append_array(lv["requires"])
		for r in all_reqs:
			var rd: BuildingDefinition = buildings.get(r["building"], null)
			if rd == null:
				errors.append("%s 的前置建築 %s 不存在" % [id, r["building"]])
			elif r["level"] > rd.max_level():
				errors.append("%s 的前置 %s Lv%d 超過最高等級" % [id, r["building"], r["level"]])


func _parse_requires(arr, owner_id: String) -> Array:
	var out: Array = []
	if not arr is Array:
		errors.append("%s requires 必須是陣列" % owner_id)
		return out
	for r in arr:
		out.append({"building": str(r.get("building", "")), "level": int(r.get("level", 1))})
	return out


func _nonneg_int(v, what: String) -> int:
	var n := int(v)
	if n < 0 or float(v) != float(n):
		errors.append("%s 必須是非負整數（目前 %s）" % [what, str(v)])
		return 0
	return n


func _validate_config() -> void:
	for key in ["tick_rate", "match_time_limit_sec", "portal_unlock_time_sec", "start_gold", "start_wood", "map"]:
		if not config.has(key):
			errors.append("match_config.json 缺少 %s" % key)
	for key in ["construction", "repair", "portal", "elf", "troll", "minion", "soul"]:
		if not config.get(key) is Dictionary:
			errors.append("match_config.json 缺少區塊 %s" % key)
