class_name MatchService
extends RefCounted
## 存活原始精靈數、25:00 時限、勝負判定與結算鎖定。

var sim: MatchSim
var result := {}   # 鎖定後：{"winner", "reason", "tick", "time_sec"}


func _init(s: MatchSim) -> void:
	sim = s


func is_locked() -> bool:
	return not result.is_empty()


## 靈魂與僕從都不算。
func alive_original_count() -> int:
	var n := 0
	for p in sim.players.values():
		if (p as PlayerAccount).alive_original:
			n += 1
	return n


func time_limit_ticks() -> int:
	return int(sim.cfg["match_time_limit_sec"]) * sim.tick_rate


## 每 tick 結束時呼叫，固定順序（規格第 5 節）：
## 1 原始精靈全滅 → 巨魔勝（同 tick 傳送門完工也一樣）
## 2 傳送門最終完成 → 精靈逃離勝
## 3 時間 ≥ 25:00 且仍有原始精靈 → 精靈援軍勝
func check_end_of_tick() -> void:
	if is_locked():
		return
	if alive_original_count() == 0:
		_lock("trolls", "all_elves_eliminated")
	elif sim.escape.is_complete():
		_lock("elves", "escaped")
	elif sim.tick >= time_limit_ticks():
		_lock("elves", "reinforcements")


func _lock(winner: String, reason: String) -> void:
	result = {"winner": winner, "reason": reason, "tick": sim.tick, "time_sec": float(sim.tick) / sim.tick_rate}
	sim.events.emit_event("match_result_locked", result.duplicate())
