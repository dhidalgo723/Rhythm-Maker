class_name RoguePrepared
extends RefCounted

## Una cancion del roguelike lista para jugarse: el chart ya transformado por
## el jefe, las reglas con flechas y consumibles aplicados, y lo necesario para
## calcular el dinero al terminar.

var boss: RogueBoss
var entry: SongEntry
var stream: AudioStream
var chart: Chart
var rules: PlayRules
## Duracion jugable (la del jefe, o la del audio si es mas corto).
var length_ms := 0.0
## Notas reales que se pueden tocar (sin senuelos ni carriles desactivados).
var notes := 0
var target_score := 0
## Usos de la mejora de ranura en esta cancion (2 con Grabadora).
var slot_uses := 1
var money_mult := 1.0
var tax := 0.0
## Consumibles que se han gastado en esta cancion.
var consumed: Array[String] = []
## Avisos para mostrar al empezar ("Cuerda Rota: carril Abajo"...).
var notices: Array[String] = []
