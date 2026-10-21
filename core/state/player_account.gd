class_name PlayerAccount
extends RefCounted
## 玩家帳戶與身分。資源皆為整數。

var id := 0
var display_name := ""
var role := "elf"                   # 開局身分："elf" / "troll"
var gold := 0
var wood := 0
var alive_original := false         # 是否為「存活的原始精靈」
var afterlife := ""                 # 精靈死後："" / "pending" / "soul" / "minion"
var unit_id := -1                   # 目前操控的單位
var job_instance_id := -1           # 個人施工動作（同時只有一項）
var authorize_soul_repair := false  # 允許靈魂修復使用我的資源
var troll_gold := 0                 # 巨魔方戰鬥收益（裝備系統另訂）


func team() -> String:
	if role == "troll" or afterlife == "minion":
		return "trolls"
	return "elves"


func to_dict() -> Dictionary:
	return {
		"id": id, "name": display_name, "role": role, "gold": gold, "wood": wood,
		"alive_original": alive_original, "afterlife": afterlife, "troll_gold": troll_gold,
	}
