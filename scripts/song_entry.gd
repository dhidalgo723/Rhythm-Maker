class_name SongEntry
extends RefCounted

## Una grabacion guardada en la biblioteca.

var slug := ""
var dir := ""
var chart: Chart


func title() -> String:
	return chart.title if chart.title != "" else slug


func audio_path() -> String:
	return dir.path_join(chart.song_path)


func note_count() -> int:
	return chart.notes.size()


## Duracion util del chart (hasta la ultima nota), en ms.
func last_note_ms() -> int:
	return 0 if chart.notes.is_empty() else chart.notes[-1].timestamp_ms
