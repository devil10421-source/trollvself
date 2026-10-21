class_name BuildingDefinition
extends RefCounted
## 靜態建築資料（唯讀）。由 DefinitionDB 從 data/buildings.json 讀入並轉成 tick 單位。

var id := ""
var display_name := ""
var category := ""
var footprint := Vector2i.ONE
var max_per_player := 0          # 0 = 不以個人計
var max_per_team := 0            # 0 = 不以隊伍計
var targetable_by_enemies := true
var damageable := true
var color := Color.WHITE
## 每級：{level,name,cost_g,cost_w,time_ticks,hp,gold_per_sec,wood_per_sec,attack,slow,vision,repair_aura,requires}
var levels: Array[Dictionary] = []
## 傳送門專用：{stage,name,cost_g,cost_w,time_ticks,reveal}
var stages: Array[Dictionary] = []
## 傳送門專用的發起前置
var requires: Array = []


func is_portal() -> bool:
	return not stages.is_empty()


func max_level() -> int:
	return levels.size()


## level 從 1 開始；超出範圍回傳空字典。
func level(n: int) -> Dictionary:
	if n < 1 or n > levels.size():
		return {}
	return levels[n - 1]
