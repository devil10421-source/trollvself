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
var house_repair_until := -1        # 樹屋修復鈕：本次修復持續到哪個 tick
var house_repair_ready := 0         # 樹屋修復鈕：冷卻結束 tick
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
