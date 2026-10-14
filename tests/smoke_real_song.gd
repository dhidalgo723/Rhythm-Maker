extends Node

## Autoplay sobre la cancion real de la biblioteca durante unos segundos.
## Valida la cadena completa: audio user:// + chart generado + reloj + juicio.
## Correr: godot --headless --path . res://tests/smoke_real_song.tscn

const SECONDS := 25.0


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var songs := Library.list_songs()
	if songs.is_empty():
		print("FAIL: biblioteca vacia"); get_tree().quit(1); return

	var entry := songs[0]
	var stream := AudioLoader.load_stream(entry.audio_path())
	if stream == null:
		print("FAIL: no carga el audio"); get_tree().quit(1); return

	var pm := PlaybackManager.new()
	add_child(pm)
	pm.start(stream, entry.chart)

	var deltas: Array[float] = []
	pm.note_hit.connect(func(_l: int, _k: Judgement.Kind, d: float) -> void: deltas.append(d))

	var notes := entry.chart.notes
	var next := 0
	while pm.is_active() and pm.get_time_ms() < SECONDS * 1000.0:
		await get_tree().process_frame
		var t := pm.get_time_ms()
		while next < notes.size() and float(notes[next].timestamp_ms) <= t:
			_press(notes[next].lane)
			next += 1
	pm.stop()

	var expected := next
	var judged := pm.judged()
	var perfects := pm.count(Judgement.Kind.PERFECT)
	var worst := 0.0
	var mean := 0.0
	for d in deltas:
		worst = maxf(worst, absf(d))
		mean += d
	if deltas.size() > 0:
		mean /= deltas.size()

	print("cancion    '%s'  (%d notas en total)" % [entry.title(), notes.size()])
	print("jugadas    %d notas en %.0f s" % [expected, SECONDS])
	var tiers: Array[String] = []
	for kind in Judgement.ORDER:
		tiers.append("%s=%d" % [Judgement.NAMES[kind], pm.count(kind)])
	print("resultado  %s  precision=%.1f%%" % [" ".join(tiers), pm.accuracy()])
	print("desfase    medio %+.1f ms, peor %.1f ms" % [mean, worst])

	# El bot pulsa en el frame siguiente a la nota, asi que su precision depende
	# del framerate: bajo carga algun hit cae en GOOD. Lo que se exige es que
	# ninguna nota se pierda y que la gran mayoria sean PERFECT.
	var ok := pm.misses == 0 and judged == expected 		and perfects >= int(expected * 0.9)
	if not ok:
		print("  esperadas %d juzgadas, hubo %d; perfect minimo %d" % [
			expected, judged, int(expected * 0.9)])
	print("SMOKE TEST %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


## Pulsa la tecla que el jugador tiene asignada de verdad, no una fija.
func _press(lane: int) -> void:
	var key := Settings.binding(Settings.SLOT_PRIMARY, lane)
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
