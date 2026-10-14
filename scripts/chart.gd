class_name Chart
extends RefCounted

const LANE_COUNT := 4
const FORMAT_VERSION := 1

## Nombre visible de la cancion.
var title := ""
## Nombre del archivo de audio, relativo a la carpeta del chart.
var song_path := ""
var bpm := 0.0
## Offset de calibracion con el que se grabo. Informativo: los timestamps ya
## estan corregidos, esto queda para poder re-derivar el crudo si hiciera falta.
var offset_ms := 0
var difficulty := "normal"
## Donde termina la partida, en ms. 0 = cuando acabe el audio. Sirve para que
## una cancion dure lo que pide su jefe aunque el audio sea mas largo.
var end_ms := 0
## Instante del primer beat, en ms. Junto con bpm da la rejilla de la cancion
## (la usa la Polirritmia para colocar tresillos). 0 si no se conoce.
var beat_offset_ms := 0
var notes: Array[ChartNote] = []


func add_note(timestamp_ms: int, lane: int, duration_ms: int = 0) -> ChartNote:
	var n := ChartNote.new(timestamp_ms, lane, duration_ms)
	notes.append(n)
	return n


## Copia independiente: los jefes y las mejoras transforman las notas de una
## copia, nunca las del chart guardado.
func duplicate_chart() -> Chart:
	var c := Chart.new()
	c.title = title
	c.song_path = song_path
	c.bpm = bpm
	c.offset_ms = offset_ms
	c.difficulty = difficulty
	c.end_ms = end_ms
	c.beat_offset_ms = beat_offset_ms
	for n in notes:
		c.notes.append(n.copy())
	return c


func beat_ms() -> float:
	return 60000.0 / bpm if bpm > 0.0 else 0.0


func sort_notes() -> void:
	notes.sort_custom(func(a: ChartNote, b: ChartNote) -> bool:
		return a.timestamp_ms < b.timestamp_ms)


func to_dict() -> Dictionary:
	sort_notes()
	var out: Array[Dictionary] = []
	for n in notes:
		out.append(n.to_dict())
	return {
		"version": FORMAT_VERSION,
		"title": title,
		"song_path": song_path,
		"bpm": bpm,
		"offset_ms": offset_ms,
		"difficulty": difficulty,
		"end_ms": end_ms,
		"beat_offset_ms": beat_offset_ms,
		"notes": out,
	}


func save_to_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return OK


static func load_from_file(path: String) -> Chart:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("No se pudo abrir el chart: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Chart invalido (no es un objeto JSON): %s" % path)
		return null

	var d: Dictionary = parsed
	var chart := Chart.new()
	chart.title = str(d.get("title", ""))
	chart.song_path = str(d.get("song_path", ""))
	chart.bpm = float(d.get("bpm", 0.0))
	chart.offset_ms = int(d.get("offset_ms", 0))
	chart.difficulty = str(d.get("difficulty", "normal"))
	chart.end_ms = int(d.get("end_ms", 0))
	chart.beat_offset_ms = int(d.get("beat_offset_ms", 0))
	for raw in d.get("notes", []):
		if typeof(raw) == TYPE_DICTIONARY:
			chart.notes.append(ChartNote.from_dict(raw))
	chart.sort_notes()
	return chart


## Ruta de chart que le corresponde a un audio: <audio>.<dificultad>.chart.json
static func chart_path_for(audio_path: String, diff: String = "normal") -> String:
	var dir := audio_path.get_base_dir()
	var base := audio_path.get_file().get_basename()
	return dir.path_join("%s.%s.chart.json" % [base, diff])
