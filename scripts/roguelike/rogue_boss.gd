class_name RogueBoss
extends RefCounted

## Una de las 10 canciones de la partida: su tamano, la cancion que toca y las
## habilidades del jefe. Las habilidades estan ocultas hasta que empieza la
## cancion (o hasta que un Setlist las revela).

var index := 0
var size: RogueCatalog.Size = RogueCatalog.Size.SMALL
var song_id := ""
var abilities: Array[String] = []
## Solo el jefe final: la combinacion (techno, metal...).
var combo_id := ""
var revealed := false
## Habilidad desactivada con un Soborno al Tecnico.
var bribed := ""


func size_name() -> String:
	return RogueCatalog.SIZE_NAMES[size]


func title() -> String:
	if combo_id != "":
		return "Jefe Final: %s" % RogueCatalog.FINAL_COMBOS[combo_id]["name"]
	return "Jefe %s" % size_name()


func active_abilities() -> Array[String]:
	var out: Array[String] = []
	for a in abilities:
		if a != bribed:
			out.append(a)
	return out


func spec() -> Dictionary:
	return RogueCatalog.SIZE_SPECS[size]


func miss_limit() -> int:
	return RogueCatalog.miss_limit(index)
