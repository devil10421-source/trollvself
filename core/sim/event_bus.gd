class_name EventBus
extends RefCounted
## 單純的事件匯流排。畫面訂閱 event_emitted；測試讀 log。

signal event_emitted(event_name: String, data: Dictionary)

const MAX_LOG := 2000

var log: Array[Dictionary] = []
var current_tick := 0


func emit_event(event_name: String, data: Dictionary = {}) -> void:
	var e := {"name": event_name, "tick": current_tick, "data": data}
	log.append(e)
	if log.size() > MAX_LOG:
		log = log.slice(log.size() - MAX_LOG)
	event_emitted.emit(event_name, data)


func count(event_name: String) -> int:
	var n := 0
	for e in log:
		if e["name"] == event_name:
			n += 1
	return n


func find_all(event_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in log:
		if e["name"] == event_name:
			out.append(e)
	return out


func clear() -> void:
	log.clear()
