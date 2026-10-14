class_name ChartNote
extends RefCounted

var timestamp_ms: int   # tiempo exacto en ms desde el inicio de la cancion
var lane: int           # 0=izq, 1=abajo, 2=arriba, 3=derecha, 4=espacio
## > 0: nota larga, hay que mantener la tecla durante este tiempo.
var duration_ms := 0
## Nota senuelo (roja): NO hay que pulsarla. Solo la crean los jefes.
var decoy := false
## Pulsaciones necesarias (2 = "Doble Golpe"). Solo la crean los jefes.
var hits := 1


func _init(t_ms: int = 0, note_lane: int = 0, dur_ms: int = 0) -> void:
	timestamp_ms = t_ms
	lane = note_lane
	duration_ms = dur_ms


func is_hold() -> bool:
	return duration_ms > 0


func end_ms() -> int:
	return timestamp_ms + duration_ms


func copy() -> ChartNote:
	var n := ChartNote.new(timestamp_ms, lane, duration_ms)
	n.decoy = decoy
	n.hits = hits
	return n


## Senuelo y doble golpe no se guardan: los anade un jefe al empezar la cancion.
func to_dict() -> Dictionary:
	var d := {"t": timestamp_ms, "lane": lane}
	if duration_ms > 0:
		d["d"] = duration_ms
	return d


static func from_dict(d: Dictionary) -> ChartNote:
	return ChartNote.new(int(d.get("t", 0)), int(d.get("lane", 0)), int(d.get("d", 0)))
