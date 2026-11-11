class_name UnitState
extends RefCounted
## 地圖上的單位：原始精靈、靈魂、主巨魔、巨魔僕從。

const KIND_ELF := "elf"
const KIND_SOUL := "soul"
const KIND_TROLL := "troll"
const KIND_MINION := "minion"

var id := 0
var kind := KIND_ELF
var player_id := 0
var team := "elves"                       # "elves" / "trolls"
var pos := Vector2.ZERO                   # 連續座標（格為單位，格中心 = x+0.5）
var hp := 0
var max_hp := 0
var alive := true
var spawned := true                       # 巨魔出場延遲前為 false
var base_speed := 4.0                     # 格/秒
var vision := 6.0

# 指令：{"type": "idle"|"move"|"build"|"repair"|"portal_work"|"attack", ...}
var order := {"type": "idle"}
var path: Array[Vector2i] = []
var repath_cooldown := 0

# 攻擊（巨魔方）
var damage := 0
var attack_interval_ticks := 10
var attack_range := 1.5
var attack_cooldown := 0
var reward_per_hp := 0.0
var reward_carry := 0.0                   # 小數收益暫存，按實際有效傷害累積
var last_building_attack_tick := -1000
var ai_enabled := false
var ai_target := {}                       # 除錯顯示用

# 狀態效果：source_id -> {"percent", "until_tick"}
var slows := {}

# 靈魂
var energy := 0.0
var energy_max := 0.0
var soul_points := 0
var soul_point_tick := 0
var soul_skills := {"repair": 1, "mark": 1, "root": 1}

# 精靈：在樹屋內（-1 = 不在）、暈眩
var inside_house := -1
var stunned_until := -1
var build_block_until := -1               # 被威嚇怒吼暫停施工

# 巨魔方：等級與經驗、回血、技能
var level := 1
var xp := 0
var last_damaged_tick := -100000
var regen_carry := 0.0
var skill_ready := {}                     # skill -> 可再用的 tick
var channel_kind := ""                    # 正在引導的技能（recall）
var channel_until := -1
var smash_ready := false
var rampage_until := -1
var rooted_until := -1
var root_immune_until := -1
var marked_until := -1
var marked_bonus := 0
var ai_mode := ""                         # "" / "retreat"


func cell() -> Vector2i:
	return GridMath.pos_to_cell(pos)


func is_original_elf() -> bool:
	return kind == KIND_ELF


## 地圖上看得到、能被選為目標、會擋路判定的狀態。
func on_map() -> bool:
	return alive and spawned and inside_house == -1


func can_move(now_tick: int) -> bool:
	return on_map() and stunned_until <= now_tick and rooted_until <= now_tick and channel_until <= now_tick


func strongest_slow(now_tick: int) -> int:
	var best := 0
	for k in slows.keys():
		var s: Dictionary = slows[k]
		if s["until_tick"] <= now_tick:
			slows.erase(k)
		else:
			best = maxi(best, int(s["percent"]))
	return best


func current_speed(now_tick: int) -> float:
	if not can_move(now_tick):
		return 0.0
	return base_speed * (100 - strongest_slow(now_tick)) / 100.0
