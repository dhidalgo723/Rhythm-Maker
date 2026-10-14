class_name PlayNote
extends RefCounted

## Una nota durante la partida: la nota del chart mas su estado. El chart no se
## toca nunca, asi que rebobinar o repetir es solo cambiar estados.

enum State {
	PENDING,   ## aun no juzgada
	HOLDING,   ## nota larga con la cabeza acertada, manteniendose
	HIT,       ## acertada
	MISSED,    ## fallada
	SKIPPED,   ## quitada sin penalizar (saltos, acordes simplificados, senuelos que pasan)
}

var note: ChartNote
var state := State.PENDING
## Pulsaciones dadas a una nota de doble golpe.
var hits_done := 0
## Puntos que dio (o quito) al juzgarse: para poder deshacerlo al rebobinar.
var score_delta := 0


func _init(chart_note: ChartNote = null) -> void:
	note = chart_note


var time_ms: int:
	get:
		return note.timestamp_ms

var lane: int:
	get:
		return note.lane


func is_live() -> bool:
	return state == State.PENDING or state == State.HOLDING
