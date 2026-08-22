class_name ChartNote
extends RefCounted

var timestamp_ms: int   # tiempo exacto en ms desde el inicio de la cancion
var lane: int           # 0=izq, 1=abajo, 2=arriba, 3=derecha


func _init(t_ms: int = 0, note_lane: int = 0) -> void:
	timestamp_ms = t_ms
	lane = note_lane


func to_dict() -> Dictionary:
	return {"t": timestamp_ms, "lane": lane}


static func from_dict(d: Dictionary) -> ChartNote:
	return ChartNote.new(int(d.get("t", 0)), int(d.get("lane", 0)))
