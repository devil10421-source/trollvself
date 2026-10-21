class_name BuildingInstance
extends RefCounted
## 執行期建築狀態。所有欄位只由 core/services 修改。

const ST_CONSTRUCTING := "constructing"   # 首次施工中（level = 0，無功能）
const ST_ACTIVE := "active"
const ST_UPGRADING := "upgrading"         # 依舊等級（level）持續運作
const ST_DESTROYED := "destroyed"

var instance_id := 0
var def_id := ""
var owner_player_id := 0                  # 傳送門 = 發起者
var team_id := "elves"
var origin := Vector2i.ZERO
var size := Vector2i.ONE
var level := 0                            # 已完成等級；施工中為 0
var state := ST_CONSTRUCTING
var hp := 0
var max_hp := 0

# 進行中的施工 / 升級工作
var job_target_level := 0
var job_progress_ticks := 0
var job_required_ticks := 0
var job_paid_g := 0
var job_paid_w := 0
var construction_damage := 0              # 首次施工期間累積受到的傷害
var construction_start_hp := 0

# 已完成等級的累計實付成本（修繕成本基準）
var total_paid_g := 0
var total_paid_w := 0

# 修繕預付餘額：payer_id -> {"g": 分子, "w": 分子}（單位 1/(100*max_hp) 枚）
var repair_credit := {}

# 塔
var attack_cooldown := 0
var slow_cooldown := 0


func is_alive() -> bool:
	return state != ST_DESTROYED


func is_functional() -> bool:
	return level >= 1 and (state == ST_ACTIVE or state == ST_UPGRADING)


func has_job() -> bool:
	return state == ST_CONSTRUCTING or state == ST_UPGRADING


func remaining_job_ticks() -> int:
	return maxi(0, job_required_ticks - job_progress_ticks)


func center() -> Vector2:
	return GridMath.rect_center(origin, size)


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id, "def_id": def_id, "owner_player_id": owner_player_id,
		"team_id": team_id, "origin": [origin.x, origin.y], "level": level, "state": state,
		"hp": hp, "max_hp": max_hp, "job_target_level": job_target_level,
		"job_progress_ticks": job_progress_ticks, "job_required_ticks": job_required_ticks,
	}
