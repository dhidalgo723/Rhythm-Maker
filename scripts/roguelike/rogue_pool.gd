class_name RoguePool
extends RefCounted

## Canciones disponibles para el modo roguelike, leidas de pool.json.
##
## Formato de pool.json:
##   {"songs": [
##     {"id": "mi_cancion", "title": "Mi canción", "size": "small",
##      "chart": "songs/mi_cancion.chart.json"},
##     ...
##   ]}
## "size" es small / medium / big / boss (la cancion 10). Una de "boss" puede
## llevar "combo" (techno, rap... ver RogueCatalog.FINAL_COMBOS): es la cancion
## del Jefe cuando sale esa combinacion. Las combinaciones sin cancion propia
## usan una de "boss" sin combo. El audio se busca por el song_path del chart,
## relativo a la carpeta del chart.

const PATH := "res://roguelike/pool.json"
const SIZES: Array[String] = ["small", "medium", "big", "boss"]

## Cada cancion: {id, title, size (String), combo (String, "" si no), entry (SongEntry)}.
var songs: Array[Dictionary] = []
## Problemas encontrados al cargar (vacio = todo bien).
var problems: Array[String] = []


static func load_pool(path: String = PATH) -> RoguePool:
	var pool := RoguePool.new()
	if not FileAccess.file_exists(path):
		pool.problems.append(Lang.t("No existe %s") % path)
		return pool
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("songs"):
		pool.problems.append(Lang.t("%s no tiene una lista \"songs\"") % path)
		return pool

	var base := path.get_base_dir()
	for raw in (parsed as Dictionary)["songs"]:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		pool._add(raw, base)
	return pool


func _add(raw: Dictionary, base: String) -> void:
	var id := str(raw.get("id", ""))
	var size := str(raw.get("size", ""))
	var combo := str(raw.get("combo", ""))
	var chart_path := base.path_join(str(raw.get("chart", "")))
	if id == "":
		problems.append(Lang.t("Una canción de pool.json no tiene id"))
		return
	if not size in SIZES:
		problems.append(Lang.t("%s: size debe ser small, medium, big o boss (es \"%s\")") % [id, size])
		return
	if combo != "" and (size != "boss" or not RogueCatalog.FINAL_COMBOS.has(combo)):
		problems.append(Lang.t("%s: combo debe ir en una canción boss y ser uno de %s") % [
			id, ", ".join(RogueCatalog.FINAL_COMBOS.keys())])
		return
	if not FileAccess.file_exists(chart_path):
		problems.append(Lang.t("%s: no existe el chart %s") % [id, chart_path])
		return
	var chart := Chart.load_from_file(chart_path)
	if chart == null or chart.notes.is_empty():
		problems.append(Lang.t("%s: el chart está vacío o roto") % id)
		return

	var entry := SongEntry.new()
	entry.slug = id
	entry.dir = chart_path.get_base_dir()
	entry.chart = chart
	if not ResourceLoader.exists(entry.audio_path()) and not FileAccess.file_exists(entry.audio_path()):
		problems.append(Lang.t("%s: no existe el audio %s") % [id, entry.audio_path()])
		return
	if raw.has("title"):
		chart.title = str(raw["title"])
	songs.append({"id": id, "title": entry.title(), "size": size, "combo": combo, "entry": entry})


func songs_of_size(size_key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in songs:
		if s["size"] == size_key:
			out.append(s)
	return out


## Canciones para el Jefe con esa combinacion: las suyas propias o, si no tiene,
## las de "boss" sin combo (y si tampoco hay, cualquiera de "boss").
func songs_for_combo(combo: String) -> Array[Dictionary]:
	var own: Array[Dictionary] = []
	var generic: Array[Dictionary] = []
	for s in songs_of_size("boss"):
		if s["combo"] == combo:
			own.append(s)
		elif s["combo"] == "":
			generic.append(s)
	if not own.is_empty():
		return own
	return generic if not generic.is_empty() else songs_of_size("boss")


## Lo que falta para poder jugar una partida completa.
func missing_sizes() -> Array[String]:
	var out: Array[String] = []
	for key in SIZES:
		if songs_of_size(key).is_empty():
			out.append(key)
	return out


func find(id: String) -> Dictionary:
	for s in songs:
		if s["id"] == id:
			return s
	return {}
