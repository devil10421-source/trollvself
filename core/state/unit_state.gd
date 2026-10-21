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


func cell() -> Vector2i:
	return GridMath.pos_to_cell(pos)


func is_original_elf() -> bool:
	return kind == KIND_ELF


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
	return base_speed * (100 - strongest_slow(now_tick)) / 100.0
