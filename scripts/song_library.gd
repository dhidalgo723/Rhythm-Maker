extends Node

## Autoload: Library. Biblioteca de grabaciones guardadas.
##
## Cada cancion vive en su propia carpeta autocontenida:
##   user://songs/<slug>/chart.json
##   user://songs/<slug>/<audio>.wav|mp3|ogg
## Se copia el audio al guardar para que la biblioteca no se rompa si el
## usuario mueve o borra el archivo original.

const SONGS_DIR := "user://songs"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SONGS_DIR)


## Todas las grabaciones guardadas, ordenadas por titulo.
func list_songs() -> Array[SongEntry]:
	var out: Array[SongEntry] = []
	var dir := DirAccess.open(SONGS_DIR)
	if dir == null:
		return out

	for slug in dir.get_directories():
		var song_dir := SONGS_DIR.path_join(slug)
		var chart_file := song_dir.path_join("chart.json")
		if not FileAccess.file_exists(chart_file):
			continue
		var chart := Chart.load_from_file(chart_file)
		if chart == null:
			continue
		if not FileAccess.file_exists(song_dir.path_join(chart.song_path)):
			push_warning("Grabacion sin audio, se omite: %s" % slug)
			continue
		var e := SongEntry.new()
		e.slug = slug
		e.dir = song_dir
		e.chart = chart
		out.append(e)

	out.sort_custom(func(a: SongEntry, b: SongEntry) -> bool:
		return a.title().naturalnocasecmp_to(b.title()) < 0)
	return out


## Guarda una grabacion: copia el audio y escribe el chart. Devuelve la carpeta.
func save_recording(chart: Chart, source_audio: String, title: String) -> String:
	var song_dir := SONGS_DIR.path_join(_make_slug(title))
	var err := DirAccess.make_dir_recursive_absolute(song_dir)
	if err != OK:
		push_error("No se pudo crear %s: %s" % [song_dir, error_string(err)])
		return ""

	var audio_name := source_audio.get_file()
	var dest_audio := song_dir.path_join(audio_name)
	# Si es una regrabacion de la misma cancion, el audio ya esta copiado.
	if not FileAccess.file_exists(dest_audio):
		err = DirAccess.copy_absolute(source_audio, dest_audio)
		if err != OK:
			push_error("No se pudo copiar el audio: %s" % error_string(err))
			return ""

	chart.title = title
	chart.song_path = audio_name
	err = chart.save_to_file(song_dir.path_join("chart.json"))
	if err != OK:
		push_error("No se pudo guardar el chart: %s" % error_string(err))
		return ""
	return song_dir


func delete_song(entry: SongEntry) -> void:
	var dir := DirAccess.open(entry.dir)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(entry.dir)


static func _make_slug(title: String) -> String:
	var slug := ""
	for c in title.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			slug += c
		elif c in " -_.":
			slug += "_"
	slug = slug.lstrip("_").rstrip("_")
	return slug if slug != "" else "cancion"
