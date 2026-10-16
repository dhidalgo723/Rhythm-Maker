extends Node

## Smoke test headless de Juego Libre.
##   1. la biblioteca encuentra la cancion instalada y su audio carga
##   2. las ventanas de cada nivel (Perfecto ... Errada) estan donde deben
##   3. cada nivel da su puntuacion, con tiempos exactos
##   4. un bot que toca a tiempo en los 5 carriles (espacio incluido) acierta todo
##   5. sin limite de fallos: no tocar nada no hace perder, solo cuenta fallos
##   6. Juego Libre con habilidades: se eligen y se aplican a una copia del chart
## Correr: godot --headless --path . res://tests/smoke_play.tscn

const TONE := "res://tests/test_tone.wav"
const K := Judgement.Kind

var _failed := false


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	await get_tree().process_frame
	await _test_library()
	_test_classify_windows()
	_test_tier_scoring()
	await _test_autoplay()
	await _test_no_miss_limit()
	await _test_free_abilities()
	if not _failed:
		print("SMOKE TEST OK")
	get_tree().quit(1 if _failed else 0)


# --- 6. Juego Libre con habilidades ---
func _test_free_abilities() -> void:
	var entry: SongEntry = RoguePool.load_pool().find("prueba_grande")["entry"]
	var notes_before := entry.chart.notes.size()

	# La lista: elegir cancion, "con habilidades", marcar tres.
	Session.free_abilities.assign([])
	var select: Control = load("res://scenes/song_select.tscn").instantiate()
	add_child(select)
	await get_tree().process_frame
	select._on_play(entry)
	await get_tree().process_frame
	_check(select._overlay != null and not select._main.visible, "al elegir cancion se pregunta como jugarla")
	select._open_abilities()
	await get_tree().process_frame
	_check(not select._ability_buttons.has("impuesto") and not select._ability_buttons.has("saqueador"),
		"las habilidades de dinero y ranura no se ofrecen en Juego Libre")
	for id in ["rasgueo", "ondulada", "senuelos"]:
		select._toggle_ability(id)
	select._toggle_ability("ondulada")   # desmarcar
	select._toggle_ability("ondulada")   # y volver a marcar
	_check(select._picked.size() == 3 and (select._play_btn as Button).text.contains("3"),
		"se marcan tantas como se quiera")
	select._back_to_list()
	_check(select._overlay == null and select._main.visible, "Esc / Cancelar vuelve a la lista")
	select.queue_free()

	# La partida: se aplican a una copia.
	Session.selected_song = entry
	Session.free_abilities.assign(["ondulada", "senuelos", "rasgueo"])
	var scene: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	var decoys := 0
	for n in scene._chart.notes:
		decoys += 1 if n.decoy else 0
	_check(scene._rules != null and scene._rules.wave, "Pista Ondulada activa")
	_check(decoys > 0, "Notas Senuelo: hay senuelos (%d)" % decoys)
	_check(scene._rules.miss_limit == 0, "con habilidades sigue sin limite de fallos")
	_check(entry.chart.notes.size() == notes_before and scene._chart != entry.chart,
		"la grabacion guardada no cambia: se juega una copia")
	scene.set_process(false)
	scene.queue_free()
	Session.free_abilities.assign([])
	Session.selected_song = null
	await get_tree().process_frame
	print("[habilidades] se eligen en la lista y se aplican a una copia del chart")


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


# --- 2. ventanas ---
func _test_classify_windows() -> void:
	# [desfase en ms, nivel esperado]. Los bordes son inclusivos.
	var cases := [
		[0.0, K.PERFECT], [45.0, K.PERFECT], [-45.0, K.PERFECT],
		[45.5, K.GOOD], [-90.0, K.GOOD],
		[90.5, K.NORMAL], [135.0, K.NORMAL],
		[-135.5, K.BAD], [165.0, K.BAD],
		[165.5, K.MISS], [-400.0, K.MISS],
	]
	for c in cases:
		var got := Judgement.classify(c[0])
		_check(got == c[1], "%+.1f ms deberia ser %s, salio %s" % [
			c[0], Judgement.NAMES[c[1]], Judgement.NAMES[got]])

	_check(Judgement.timing_hint(K.GOOD, -60.0) == "pronto", "un toque adelantado deberia decir pronto")
	_check(Judgement.timing_hint(K.BAD, 150.0) == "tarde", "un toque atrasado deberia decir tarde")
	_check(Judgement.timing_hint(K.PERFECT, 20.0) == "", "un perfecto no necesita pista")
	print("[ventanas] Perfecto 45 / Bueno 90 / Normal 135 / Vaya... 165 ms, simetricas")


# --- 3. puntuacion por nivel, sin depender del framerate ---
func _test_tier_scoring() -> void:
	# Notas lejanas en el tiempo: el reloj real no llega a ellas durante el
	# test, asi que nada se marca como errada por su cuenta.
	var base := 60000
	var chart := Chart.new()
	for i in 6:
		chart.add_note(base + i * 1000, 0)

	var pm := PlaybackManager.new()
	add_child(pm)
	pm.start(_tone_stream(), chart)

	# [desfase, nivel esperado, puntos esperados (base + bonus de combo)]
	var plays := [
		[0.0, K.PERFECT, 350 + 0],
		[30.0, K.PERFECT, 350 + 1],
		[-60.0, K.GOOD, 200 + 2],
		[110.0, K.NORMAL, 100 + 3],
		[-150.0, K.BAD, 50 + 4],
	]
	var expected_score := 0
	for i in plays.size():
		var play: Array = plays[i]
		var before := pm.score
		var got := pm.judge_press(0, base + i * 1000 + play[0])
		_check(got == play[1], "toque %d: esperaba %s, salio %s" % [
			i, Judgement.NAMES[play[1]], Judgement.NAMES[got]])
		_check(pm.score - before == play[2], "toque %d: esperaba +%d puntos, dio %+d" % [
			i, play[2], pm.score - before])
		expected_score += play[2]

	_check(pm.combo == 5, "Vaya... no deberia romper el combo (combo %d)" % pm.combo)

	# Toque a 300 ms de la siguiente nota: Errada, y la nota sigue esperando.
	var got_miss := pm.judge_press(0, base + 5000 - 300)
	_check(got_miss == K.MISS, "un toque a 300 ms deberia ser Errada")
	_check(pm.combo == 0, "la Errada deberia romper el combo")
	_check(pm.score == expected_score - 100, "la Errada deberia restar 100 (score %d)" % pm.score)
	_check(pm.lane_head(0) == 5, "una Errada sin nota no deberia consumir la nota siguiente")

	for kind in Judgement.ORDER:
		var want := 2 if kind == K.PERFECT else 1
		_check(pm.count(kind) == want, "%s: esperaba %d, hubo %d" % [
			Judgement.NAMES[kind], want, pm.count(kind)])

	# (2*1.0 + 0.75 + 0.5 + 0.25 + 0) / 6 = 58.33 %
	_check(absf(pm.accuracy() - 58.333) < 0.01, "precision %.3f, esperaba 58.333" % pm.accuracy())

	print("[niveles] P/P/B/N/V/E -> score %d, precision %.1f%%" % [pm.score, pm.accuracy()])
	pm.stop()
	pm.queue_free()


func _make_chart(times: Array, spread: bool) -> Chart:
	var c := Chart.new()
	for i in times.size():
		c.add_note(int(times[i]), (i % Lanes.COUNT) if spread else 0)
	return c


func _tone_stream() -> AudioStream:
	return AudioLoader.load_stream(ProjectSettings.globalize_path(TONE))


# --- 4. autoplay en los 5 carriles ---
func _test_autoplay() -> void:
	var times := [600, 1000, 1400, 1800, 2200]   # un carril cada una, espacio incluido
	var pm := PlaybackManager.new()
	add_child(pm)
	pm.start(_tone_stream(), _make_chart(times, true))

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
	pm.stop()

	print("[autoplay] perfecto=%d bueno=%d errada=%d score=%d precision=%.1f%%" % [
		pm.count(K.PERFECT), pm.count(K.GOOD), pm.misses, pm.score, pm.accuracy()])
	_check(pm.hits() == times.size(), "se esperaban %d aciertos, hubo %d" % [times.size(), pm.hits()])
	_check(pm.misses == 0, "el bot fallo %d veces tocando a tiempo" % pm.misses)
	# El bot pulsa en el frame siguiente a la nota: un tiron del sistema puede
	# empujar uno a Bueno. Se tolera uno; mas ya seria un problema de timing.
	_check(pm.count(K.PERFECT) >= times.size() - 1,
		"casi todos deberian ser Perfecto (%d)" % pm.count(K.PERFECT))
	pm.queue_free()


# --- 5. sin limite de fallos ---
func _test_no_miss_limit() -> void:
	var times: Array = []
	# 20 notas: mas de los 15 fallos con los que antes se perdia, y todas
	# dentro del audio de prueba.
	for i in 20:
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

	print("[sin limite] errada=%d  perdio=%s  score=%d" % [pm.misses, lost[0], pm.score])
	_check(not lost[0], "en Juego Libre no se pierde por fallos")
	_check(pm.misses == times.size(), "se cuentan todos los fallos (%d de %d)" % [pm.misses, times.size()])
	_check(pm.score == 0, "el score no deberia bajar de 0, quedo en %d" % pm.score)
	pm.queue_free()


## Pulsa la tecla que el jugador tiene asignada de verdad, no una fija: si no,
## el test fallaria en cuanto alguien cambie sus teclas en Ajustes.
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
