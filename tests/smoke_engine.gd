extends Node

## Mecanicas del motor que usan las mejoras y los jefes, con tiempos exactos.
## Las notas van lejos (a partir de 60 s) para que el reloj real no llegue a
## ellas: los pasos del tiempo se simulan llamando a _sweep_lane / judge_*.
## Correr: godot --headless --path . res://tests/smoke_engine.tscn

const TONE := "res://tests/test_tone.wav"
const K := Judgement.Kind
const B := 60000   # base de tiempos

var _failed := false
var _stream: AudioStream


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	_stream = AudioLoader.load_stream(ProjectSettings.globalize_path(TONE))

	_test_holds()
	_test_decoys()
	_test_double_hit()
	_test_disabled_lanes()
	_test_windows()
	_test_forced_effects()
	_test_risk_and_shields()
	_test_bis()
	_test_boss_shield()
	_test_key_rotation()
	_test_erase_and_skip()
	_test_steal_and_boo()
	await _test_clock_tempo_and_seek()
	await _test_end_ms()

	print("SMOKE TEST %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("  FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


func _pm(chart: Chart, rules: PlayRules = null) -> PlaybackManager:
	var pm := PlaybackManager.new()
	add_child(pm)
	pm.start(_stream, chart, rules)
	pm.set_process(false)   # el tiempo lo movemos a mano
	return pm


func _done(pm: PlaybackManager) -> void:
	pm.stop()
	pm.queue_free()


func _chart(spec: Array) -> Chart:
	var c := Chart.new()
	for s in spec:
		var n: ChartNote = c.add_note(B + int(s[0]), int(s[1]), int(s[2]) if s.size() > 2 else 0)
		if s.size() > 3:
			if s[3] == "decoy":
				n.decoy = true
			elif s[3] == "x2":
				n.hits = 2
	return c


func _test_holds() -> void:
	var pm := _pm(_chart([[0, 0, 1000], [2000, 1, 1000], [4000, 2, 1000], [6000, 3, 1000]]))
	# Completa: mantener hasta el final da el bonus.
	_check(pm.judge_press(0, B) == K.PERFECT, "cabeza de larga deberia ser perfecta")
	var before := pm.score
	pm._sweep_lane(0, B + 1000)
	_check(pm.score - before == Judgement.HOLD_BONUS, "mantener hasta el final da el bonus")
	_check(pm.misses == 0, "una larga completa no es fallo")

	# Rota: soltar a mitad cuenta como fallo.
	pm.judge_press(1, B + 2000)
	pm.judge_release(1, B + 2400)
	_check(pm.misses == 1, "soltar a mitad deberia romper la larga")

	# Soltar casi al final (dentro de la tolerancia) cuenta como completa.
	pm.judge_press(2, B + 4000)
	pm.judge_release(2, B + 4900)
	_check(pm.misses == 1, "soltar a 100 ms del final deberia valer")

	# Sustain: soltar pronto no la rompe.
	pm.add_effect(TimedEffect.SUSTAIN, B + 5000, B + 8000)
	pm.judge_press(3, B + 6000)
	pm.judge_release(3, B + 6200)
	_check(pm.misses == 1, "con Pedal de Sustain soltar pronto no deberia romperla")
	_done(pm)

	# Flecha de Hielo: igual, pero solo en su carril.
	var rules := PlayRules.new()
	rules.unbreakable_hold_lanes = [0]
	pm = _pm(_chart([[0, 0, 1000], [0, 1, 1000]]), rules)
	pm.judge_press(0, B)
	pm.judge_press(1, B)
	pm.judge_release(0, B + 100)
	pm.judge_release(1, B + 100)
	_check(pm.misses == 1, "Hielo protege su carril y solo ese (fallos %d)" % pm.misses)
	_done(pm)
	print("[largas] completar, romper, tolerancia, Sustain y Hielo")


func _test_decoys() -> void:
	var pm := _pm(_chart([[0, 0, 0, "decoy"], [1000, 0, 0, "decoy"], [2000, 0]]))
	_check(pm.judge_press(0, B + 10) == K.MISS, "pulsar un senuelo es fallo")
	_check(pm.misses == 1, "el senuelo pulsado cuenta como fallo")
	pm._sweep_lane(0, B + 1500)
	_check(pm.misses == 1, "dejar pasar un senuelo no es fallo")
	_check(pm.judge_press(0, B + 2000) == K.PERFECT, "la nota real tras los senuelos sigue ahi")
	_check(pm.total_notes() == 1, "los senuelos no cuentan como notas del chart")
	_done(pm)
	print("[senuelos] pulsarlos falla, dejarlos pasar no")


func _test_double_hit() -> void:
	var pm := _pm(_chart([[0, 0, 0, "x2"], [1000, 0, 0, "x2"]]))
	_check(pm.judge_press(0, B) == PlaybackManager.PARTIAL, "el primer golpe es parcial")
	_check(pm.judge_press(0, B + 20) == K.PERFECT, "el segundo golpe la acierta")
	_check(pm.hits() == 1, "un doble golpe es un solo acierto")
	pm.judge_press(0, B + 1000)   # solo un golpe...
	pm._sweep_lane(0, B + 1500)   # ...y se pasa
	_check(pm.misses == 1, "quedarse en un golpe de dos es fallo")
	_done(pm)
	print("[doble golpe] dos pulsaciones, una sola no basta")


func _test_disabled_lanes() -> void:
	var rules := PlayRules.new()
	rules.disabled_lanes = [1]
	var pm := _pm(_chart([[0, 1], [0, 2]]), rules)
	_check(pm.total_notes() == 1, "las notas de un carril desactivado desaparecen")
	_check(pm.judge_press(1, B) == PlaybackManager.IGNORED, "pulsar un carril desactivado no hace nada")
	_check(pm.misses == 0, "y no penaliza")
	_done(pm)
	print("[carriles desactivados] sin notas y sin penalizar")


func _test_windows() -> void:
	var rules := PlayRules.new()
	rules.lane_window_mult[0] = 1.5      # Flecha Iman en el carril 0
	var pm := _pm(_chart([[0, 0], [0, 1]]), rules)
	_check(pm.judge_press(0, B + 60) == K.PERFECT, "Iman: 60 ms es perfecto con la ventana x1.5 (67 ms)")
	_check(pm.judge_press(1, B + 60) == K.GOOD, "sin Iman, 60 ms es bueno")
	_done(pm)

	rules = PlayRules.new()
	rules.perfect_window_mult = 0.5
	pm = _pm(_chart([[0, 0]]), rules)
	_check(pm.judge_press(0, B + 30) == K.GOOD, "Ventana Estrecha: 30 ms ya no es perfecto")
	_done(pm)

	pm = _pm(_chart([[0, 0], [1000, 0]]))
	pm.add_effect(TimedEffect.WINDOW_X2, B, B + 2000)
	_check(pm.judge_press(0, B + 300) == K.BAD, "Afinador: 300 ms entra con la ventana doble")
	_done(pm)
	print("[ventanas] Iman, Ventana Estrecha, Afinador")


func _test_forced_effects() -> void:
	var pm := _pm(_chart([[0, 0], [1000, 1], [2000, 2], [3000, 3]]))
	pm.add_effect(TimedEffect.ALWAYS_PERFECT, B - 500, B + 1500)
	_check(pm.judge_press(0, B + 300) == K.PERFECT, "Metronomo: 300 ms tarde sigue siendo perfecto")
	pm.add_effect(TimedEffect.ALWAYS_GOOD, B + 1500, B + 2500)
	_check(pm.judge_press(2, B + 2250) == K.GOOD, "Pua: siempre bueno")
	pm.add_effect(TimedEffect.ANY_KEY_PERFECT, B + 2500, B + 3500)
	_check(pm.judge_press(4, B + 3000) == K.PERFECT, "Beat Drop: el espacio acierta la nota de la derecha")
	_check(pm.lane_head(3) == 1, "y la consume")
	_done(pm)
	print("[efectos forzados] Metronomo, Pua, Beat Drop")


func _test_risk_and_shields() -> void:
	var rules := PlayRules.new()
	rules.risk_free_until_ms = B + 500
	rules.shield_lanes = [1]
	rules.lane_miss_weight[2] = 2        # Flecha de Cristal
	var pm := _pm(_chart([[0, 0], [1000, 1], [2000, 1], [3000, 2]]), rules)
	pm._sweep_lane(0, B + 400)
	_check(pm.misses == 0, "Ensayo: fallar al principio no cuenta")
	pm._sweep_lane(1, B + 1500)
	_check(pm.misses == 0, "Escudo: el primer fallo del carril no cuenta")
	pm._sweep_lane(1, B + 2500)
	_check(pm.misses == 1, "Escudo: el segundo si")
	pm._sweep_lane(2, B + 3500)
	_check(pm.misses == 3, "Cristal: su fallo cuenta doble (fallos %d)" % pm.misses)
	_done(pm)
	print("[riesgo] Ensayo, Flecha Escudo, Flecha de Cristal")


func _test_bis() -> void:
	var rules := PlayRules.new()
	rules.miss_limit = 2
	rules.bis = true
	var pm := _pm(_chart([[0, 0], [100, 0], [200, 0], [300, 0], [400, 0]]), rules)
	var lost := [false]
	var saved := [false]
	pm.game_over.connect(func() -> void: lost[0] = true)
	pm.bis_triggered.connect(func() -> void: saved[0] = true)
	pm._sweep_lane(0, B + 2500)
	_check(saved[0], "Bis deberia saltar al pasar el limite")
	_check(lost[0], "Bis salva una sola vez: al volver a pasarlo se pierde")
	_done(pm)
	print("[bis] sobrevive una vez justo en el limite")


func _test_boss_shield() -> void:
	var rules := PlayRules.new()
	rules.boss_shield_perfects = 3
	var spec: Array = []
	for i in 6:
		spec.append([i * 1000, 0])
	var pm := _pm(_chart(spec), rules)
	for i in 3:
		pm.judge_press(0, B + i * 1000)
	_check(pm.score == 0, "con el escudo del jefe no se puntua")
	_check(not pm.boss_shield_up(), "3 perfectos seguidos lo rompen")
	pm.judge_press(0, B + 3000)
	_check(pm.score > 0, "roto el escudo se vuelve a puntuar")
	pm._update_boss_shield(B + 3000 + rules.boss_shield_regen_ms)
	_check(pm.boss_shield_up(), "el escudo se regenera")
	_done(pm)
	print("[escudo del jefe] bloquea, se rompe y se regenera")


func _test_key_rotation() -> void:
	var rules := PlayRules.new()
	rules.key_rotation_every = 2
	var pm := _pm(_chart([[0, 0], [100, 1]]), rules)
	_check(pm.remap_lane(0) == 0, "sin rotar, cada tecla a su carril")
	pm.judge_press(0, B)
	pm.judge_press(1, B + 100)
	_check(pm.key_shift == 1, "tras 2 notas las flechas rotan")
	_check(pm.remap_lane(0) == 1 and pm.remap_lane(3) == 0, "la rotacion es circular")
	_check(pm.remap_lane(Lanes.SPACE) == Lanes.SPACE, "el espacio no rota")
	_done(pm)
	print("[cambio de clave] rota las 4 flechas, no el espacio")


func _test_erase_and_skip() -> void:
	var pm := _pm(_chart([[0, 0], [1000, 0], [2000, 1], [3000, 1], [4000, 2], [4000, 3]]))
	pm.judge_press(0, B)               # acierto
	pm._sweep_lane(0, B + 1500)        # fallo a los 1000
	pm._sweep_lane(1, B + 2500)        # fallo a los 2000
	var score_before := pm.score
	_check(pm.misses == 2, "dos fallos antes de rebobinar")
	var erased := pm.erase_misses_since(B + 1500)
	_check(erased == 1 and pm.misses == 1, "Cinta: borra solo los fallos del tramo")
	_check(pm.score == score_before + 100, "y devuelve los puntos que quito")
	_check(pm.lane_head(1) == 0, "la nota fallada vuelve a estar viva")
	_check(pm.erase_all_misses() == 1 and pm.misses == 0, "Distorsion: borra todos")

	# Acordes: quitar todas menos una a la vez.
	var removed := pm.skip_notes(B + 3500, B + 4500, func(pn: PlayNote) -> bool: return pn.lane == 3)
	_check(removed == 1, "Arreglo Simplificado quita la nota sobrante del acorde")

	# Pad de DJ: mover al espacio.
	var moved := pm.move_notes_to_lane(B + 2500, B + 3500, Lanes.SPACE)
	_check(moved == 1, "Pad de DJ mueve la nota al espacio")
	_check(pm.judge_press(Lanes.SPACE, B + 3000) == K.PERFECT, "y se acierta con el espacio")
	_done(pm)
	print("[tiempo] Cinta, Distorsion, Arreglo Simplificado, Pad de DJ")


func _test_steal_and_boo() -> void:
	var rules := PlayRules.new()
	rules.steal_after_misses = 3
	rules.scroll_per_miss = 0.1
	var pm := _pm(_chart([]), rules)
	var stolen := [0]
	pm.slot_stolen.connect(func() -> void: stolen[0] += 1)
	for i in 3:
		pm.judge_press(0, B + i * 10)
	_check(stolen[0] == 1, "Saqueador: 3 fallos seguidos roban la mejora")
	_check(is_equal_approx(pm.scroll_multiplier(B), 1.3), "Abucheo: cada fallo acelera (x%.2f)" % pm.scroll_multiplier(B))
	_done(pm)

	rules = PlayRules.new()
	rules.crescendo_to = 1.5
	pm = _pm(_chart([]), rules)
	var length := pm.song_length_ms()
	_check(is_equal_approx(pm.scroll_multiplier(0.0), 1.0), "Crescendo empieza normal")
	_check(is_equal_approx(pm.scroll_multiplier(length), 1.5), "y acaba en x1.5")
	_done(pm)
	print("[jefes] Saqueador, Abucheo, Crescendo")


func _test_clock_tempo_and_seek() -> void:
	var pm := PlaybackManager.new()
	add_child(pm)
	pm.start(_stream, Chart.new())
	await get_tree().create_timer(0.3).timeout
	# Como lo hace el juego: un efecto de tempo, que el manager aplica al reloj.
	var t0 := pm.get_time_ms()
	var slow := pm.add_effect(TimedEffect.TEMPO, t0, t0 + 100000.0, {"tempo": 0.5})
	await get_tree().process_frame
	await get_tree().process_frame
	var c0 := pm.clock.get_time_ms()
	await get_tree().create_timer(0.6).timeout
	var advanced := pm.clock.get_time_ms() - c0
	_check(is_equal_approx(pm.clock.get_tempo(), 0.5), "el efecto deberia poner el reloj a tempo 0.5")
	_check(is_equal_approx(pm.clock.player.pitch_scale, 0.5), "y el audio a la mitad de velocidad")
	_check(advanced > 220 and advanced < 420,
		"a tempo 0.5, 0.6 s reales deberian ser ~300 ms de cancion (fueron %.0f)" % advanced)
	slow.end_ms = 0.0   # fin del efecto
	# process_frame se emite ANTES de los _process: hacen falta dos para que el
	# manager haya corrido al menos una vez.
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_equal_approx(pm.clock.get_tempo(), 1.0), "al acabar el efecto vuelve a tempo normal")
	pm.clock.seek(2000.0)
	_check(absf(pm.clock.get_time_ms() - 2000.0) < 40, "seek deberia llevar el reloj a 2000 ms")
	await get_tree().create_timer(0.3).timeout
	_check(pm.clock.get_time_ms() > 2100, "tras el seek el reloj sigue corriendo desde ahi")
	_done(pm)
	print("[reloj] tempo x%.1f y saltos" % 0.5)


## Una cancion con end_ms acaba ahi aunque el audio siga.
func _test_end_ms() -> void:
	var c := Chart.new()
	c.end_ms = 800
	var pm := PlaybackManager.new()
	add_child(pm)
	var ended := [false]
	pm.song_ended.connect(func() -> void: ended[0] = true)
	pm.start(_stream, c)
	_check(is_equal_approx(pm.song_length_ms(), 800.0), "la duracion jugable es end_ms")
	var deadline := Time.get_ticks_msec() + 3000
	while not ended[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(ended[0], "la cancion deberia terminar en end_ms")
	_check(pm.clock.get_time_ms() < 1500, "y no seguir hasta el final del audio (3 s)")
	pm.queue_free()
	print("[duracion] la partida acaba en end_ms")
