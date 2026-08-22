extends Node

## Smoke test headless del modo juego.
##   1. la biblioteca encuentra la cancion instalada y su audio carga
##   2. un bot que toca cada nota a tiempo saca solo PERFECT
##   3. no tocar nada acaba en game over al pasar de MAX_MISSES
## Correr: godot --headless --path . res://tests/smoke_play.tscn

const TONE := "res://tests/test_tone.wav"
const KEYS := [KEY_LEFT, KEY_DOWN, KEY_UP, KEY_RIGHT]

var _failed := false


func _ready() -> void:
	await get_tree().process_frame
	await _test_library()
	await _test_autoplay()
	await _test_game_over()
	if not _failed:
		print("SMOKE TEST OK")
	get_tree().quit(1 if _failed else 0)


func _fail(msg: String) -> void:
	_failed = true
	print("FAIL: %s" % msg)
	push_error("FAIL: %s" % msg)


func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond


# --- 1. biblioteca ---
func _test_library() -> void:
	var songs := Library.list_songs()
	print("[biblioteca] %d grabacion(es)" % songs.size())
	if not _check(songs.size() > 0, "la biblioteca esta vacia"):
		return
	for e in songs:
		var stream := AudioLoader.load_stream(e.audio_path())
		if not _check(stream != null, "no carga el audio de %s" % e.title()):
			continue
		print("  '%s'  %d notas  audio %.1f s  bpm %.1f  ultima nota %.1f s" % [
			e.title(), e.note_count(), stream.get_length(), e.chart.bpm,
			e.last_note_ms() / 1000.0])
		_check(e.note_count() > 0, "%s no tiene notas" % e.title())
		_check(e.last_note_ms() <= int(stream.get_length() * 1000.0) + 500,
			"%s tiene notas mas alla del final del audio" % e.title())


func _make_chart(times: Array, spread: bool) -> Chart:
	var c := Chart.new()
	for i in times.size():
		c.add_note(int(times[i]), (i % Lanes.COUNT) if spread else 0)
	return c


func _tone_stream() -> AudioStream:
	return AudioLoader.load_stream(ProjectSettings.globalize_path(TONE))


# --- 2. autoplay: todo perfect ---
func _test_autoplay() -> void:
	var times := [600, 1000, 1400, 1800, 2200]
	var pm := PlaybackManager.new()
	add_child(pm)
	pm.start(_tone_stream(), _make_chart(times, true))

	var hits := 0
	var fired := 0
	while pm.is_active() and fired < times.size():
		await get_tree().process_frame
		var t := pm.get_time_ms()
		if fired < times.size() and t >= float(times[fired]):
			_press(fired % Lanes.COUNT)
			fired += 1
	# margen para que se juzguen los ultimos eventos
	for i in 20:
		await get_tree().process_frame
	hits = pm.perfects + pm.goods
	pm.stop()

	print("[autoplay] perfect=%d good=%d fallos=%d score=%d precision=%.1f%%" % [
		pm.perfects, pm.goods, pm.misses, pm.score, pm.accuracy()])
	_check(hits == times.size(), "se esperaban %d aciertos, hubo %d" % [times.size(), hits])
	_check(pm.misses == 0, "el bot fallo %d veces tocando a tiempo" % pm.misses)
	_check(pm.perfects == times.size(), "no todos fueron PERFECT (%d)" % pm.perfects)
	_check(pm.score > 0, "el score no subio")
	pm.queue_free()


# --- 3. game over al pasar de MAX_MISSES ---
func _test_game_over() -> void:
	var times: Array = []
	for i in Judgement.MAX_MISSES + 3:
		times.append(500 + i * 100)

	var pm := PlaybackManager.new()
	add_child(pm)
	var lost := [false]
	pm.game_over.connect(func() -> void: lost[0] = true)
	pm.start(_tone_stream(), _make_chart(times, true))

	var guard := 0
	while pm.is_active() and guard < 1200:
		await get_tree().process_frame
		guard += 1

	print("[game over] fallos=%d  perdio=%s  score=%d" % [pm.misses, lost[0], pm.score])
	_check(lost[0], "no se disparo game_over sin tocar nada")
	_check(pm.misses == Judgement.MAX_MISSES + 1,
		"se esperaba perder exactamente al fallo %d, hubo %d" % [
			Judgement.MAX_MISSES + 1, pm.misses])
	_check(pm.score == 0, "el score no deberia bajar de 0, quedo en %d" % pm.score)
	pm.queue_free()


func _press(lane: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = KEYS[lane]
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = KEYS[lane]
	up.pressed = false
	Input.parse_input_event(up)
