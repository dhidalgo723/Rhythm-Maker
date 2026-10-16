extends Node

## Arranca Juego Libre con un bot y guarda capturas del playfield.
## Correr: godot --path . --disable-vsync res://tests/capture.tscn
## (con VSync, una ventana lanzada en segundo plano puede quedar a ~6 FPS y el
## bot, que solo pulsa una vez por frame, llega tarde a todas las notas)
##
## Usa la cancion real pero con una copia del chart EN MEMORIA donde algunas
## notas pasan al carril espacio, para ver los cinco carriles en accion sin
## tocar los charts guardados. Silencia el audio: solo interesa la imagen.

const SONG_TITLE := "Por si un dia vuelves"
const SHOTS := [5.6, 6.5]
## El bot pulsa tarde a proposito para que se vea un juicio que no es Perfecto.
const BOT_OFFSET_MS := 70.0


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var entry := _pick_song()
	if entry == null:
		print("no hay canciones"); get_tree().quit(1); return

	var copy := SongEntry.new()
	copy.slug = entry.slug
	copy.dir = entry.dir
	copy.chart = Chart.new()
	copy.chart.title = entry.chart.title
	copy.chart.song_path = entry.chart.song_path
	for i in entry.chart.notes.size():
		var n: ChartNote = entry.chart.notes[i]
		copy.chart.add_note(n.timestamp_ms, Lanes.SPACE if i % 3 == 1 else n.lane)
	Session.selected_song = copy

	var scene: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(scene)

	var t := 0.0
	var shot := 0
	var next := 0
	var held := -1
	while shot < SHOTS.size():
		await get_tree().process_frame
		t += get_process_delta_time()
		if get_process_delta_time() > 0.05:
			print("FRAME LENTO %.0f ms a t=%.2f s" % [get_process_delta_time() * 1000.0, t])

		var pm: PlaybackManager = scene._pm
		if pm != null and not pm.note_hit.is_connected(_on_hit):
			pm.note_hit.connect(_on_hit)
			pm.note_missed.connect(_on_miss.bind(pm))
		if held != -1:
			_send(held, false)
			held = -1
		if pm != null and pm.is_active():
			var song_t := pm.get_time_ms()
			var notes := copy.chart.notes
			while next < notes.size() and song_t >= notes[next].timestamp_ms + BOT_OFFSET_MS:
				held = notes[next].lane
				print("BOT t=%.0f pulsa carril %d (nota %d)" % [song_t, held, notes[next].timestamp_ms])
				_send(held, true)
				next += 1

		if t >= SHOTS[shot]:
			await RenderingServer.frame_post_draw
			var path := "res://tests/shot_%d.png" % shot
			var err := get_viewport().get_texture().get_image().save_png(
				ProjectSettings.globalize_path(path))
			print("captura %s a los %.1f s -> %s" % [path, t, error_string(err)])
			shot += 1
	get_tree().quit(0)


func _pick_song() -> SongEntry:
	var songs := Library.list_songs()
	for e in songs:
		if e.title() == SONG_TITLE:
			return e
	return songs[0] if not songs.is_empty() else null


func _send(lane: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = Settings.binding(Settings.SLOT_PRIMARY, lane)
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _on_hit(lane: int, kind: Judgement.Kind, delta: float) -> void:
	print("  HIT carril %d %s %+.0f ms" % [lane, Judgement.NAMES[kind], delta])


func _on_miss(lane: int, pm: PlaybackManager) -> void:
	print("  MISS carril %d a t=%.0f (cabeza %d)" % [lane, pm.get_time_ms(), pm.lane_head(lane)])
