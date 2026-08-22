extends Node

## Verifica la calibracion de latencia y la pausa.
## Correr: godot --headless --path . res://tests/smoke_calibration.tscn

const TONE := "res://tests/test_tone.wav"

var _failed := false


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var original_offset := Settings.offset_ms

	_test_metronome_stream()
	_test_median()
	_test_tap_maths()
	await _test_live_calibration()
	await _test_clock_pause()

	Settings.offset_ms = original_offset
	Settings.save_settings()

	print("SMOKE TEST %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("  FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


# --- metronomo ---
func _test_metronome_stream() -> void:
	var bpm := 100.0
	var beats := 8
	var stream := Metronome.make_stream(bpm, beats)
	_check(stream != null, "no se genero el metronomo")

	var expected := beats * 60.0 / bpm + Metronome.TAIL_S
	_check(absf(stream.get_length() - expected) < 0.05,
		"duracion %.2f s, esperada %.2f s" % [stream.get_length(), expected])

	# Cada click debe caer justo en su beat: se comprueba que hay energia ahi y
	# silencio a mitad de camino entre dos clicks.
	var loud_on_beat := _peak_around(stream, Metronome.beat_time_ms(bpm, 3) / 1000.0)
	var quiet_between := _peak_around(stream, Metronome.beat_time_ms(bpm, 3) / 1000.0 + 0.3)
	_check(loud_on_beat > 5000, "no hay click en el beat 3 (pico %d)" % loud_on_beat)
	_check(quiet_between < 100, "deberia haber silencio entre clicks (pico %d)" % quiet_between)
	print("[metronomo] %d clicks, %.2f s, pico en beat %d vs entre beats %d" % [
		beats, stream.get_length(), loud_on_beat, quiet_between])


## Muestra maxima en una ventana de 20 ms alrededor de un instante.
## stream.data devuelve una COPIA del buffer en cada acceso, asi que se saca
## fuera del bucle: leerlo dentro copiaria megabytes por muestra.
func _peak_around(stream: AudioStreamWAV, at_s: float) -> int:
	var pcm := stream.data
	var start := int(at_s * Metronome.MIX_RATE) * 2
	var peak := 0
	for i in int(0.020 * Metronome.MIX_RATE):
		var index := start + i * 2
		if index + 1 >= pcm.size():
			break
		peak = maxi(peak, absi(pcm.decode_s16(index)))
	return peak


# --- estadistica ---
func _test_median() -> void:
	_check(CalibrationManager.median([1.0, 2.0, 3.0]) == 2.0, "mediana impar mal")
	_check(CalibrationManager.median([1.0, 2.0, 3.0, 4.0]) == 2.5, "mediana par mal")
	_check(CalibrationManager.median([]) == 0.0, "mediana vacia deberia ser 0")

	# La mediana debe aguantar un par de toques disparatados; la media no.
	var noisy: Array[float] = [40.0, 42.0, 38.0, 41.0, 39.0, 500.0, -400.0]
	_check(absf(CalibrationManager.median(noisy) - 40.0) < 2.0,
		"la mediana se fue con los valores extremos: %.1f" % CalibrationManager.median(noisy))
	print("[mediana] robusta ante toques disparatados")


## El calculo de desfase, sin audio de por medio.
func _test_tap_maths() -> void:
	var cal := CalibrationManager.new()
	add_child(cal)
	var beat := cal.beat_ms()

	# Toques durante la entrada: no cuentan.
	_check(not cal.register_tap(beat * 1.0), "un toque en la entrada no deberia contar")
	_check(cal.taps() == 0, "se conto un toque de la entrada")

	# 10 toques 45 ms tarde sobre beats medidos.
	for i in 10:
		var beat_index := CalibrationManager.LEAD_BEATS + i
		_check(cal.register_tap(beat * beat_index + 45.0), "el toque %d deberia contar" % i)
	_check(cal.taps() == 10, "se esperaban 10 toques, hubo %d" % cal.taps())
	_check(cal.offset_ms() == 45, "el offset deberia ser +45 ms, dio %d" % cal.offset_ms())
	_check(cal.spread_ms() < 1.0, "toques identicos deberian dar variacion ~0")
	_check(cal.has_enough_taps(), "10 toques deberian bastar")

	# Un toque demasiado lejos de su click es un fallo del jugador, no latencia.
	_check(not cal.register_tap(beat * 8 + beat * 0.45),
		"un toque a 45%% del beat deberia descartarse")
	_check(cal.register_tap(beat * 8 + beat * 0.3),
		"un toque a 30%% del beat si deberia contar")
	_check(cal.taps() == 11, "solo deberia haberse sumado el toque valido")

	print("[toques] offset %+d ms a partir de toques 45 ms tarde" % cal.offset_ms())
	cal.queue_free()


## La cadena entera con audio real: metronomo sonando y toques inyectados.
func _test_live_calibration() -> void:
	var cal := CalibrationManager.new()
	add_child(cal)
	cal.start()

	var beat := cal.beat_ms()
	var next := CalibrationManager.LEAD_BEATS
	var guard := 0
	while cal.is_running() and next < cal.total_beats() and guard < 3000:
		await get_tree().process_frame
		guard += 1
		var t := cal.clock.get_time_ms()
		if t >= beat * next:
			cal.register_tap(beat * next)   # toque perfecto, sin desfase
			next += 1
	cal.stop()

	_check(cal.taps() >= CalibrationManager.MIN_TAPS,
		"se esperaban al menos %d toques, hubo %d" % [CalibrationManager.MIN_TAPS, cal.taps()])
	_check(absf(cal.offset_ms()) <= 2,
		"toques perfectos deberian dar offset ~0, dio %+d ms" % cal.offset_ms())
	print("[en vivo] %d toques, offset %+d ms, variacion %.1f ms" % [
		cal.taps(), cal.offset_ms(), cal.spread_ms()])
	cal.queue_free()


## Pausar y reanudar no debe adelantar el reloj de cancion.
func _test_clock_pause() -> void:
	var clock := SongClock.new()
	add_child(clock)
	clock.set_stream(AudioLoader.load_stream(ProjectSettings.globalize_path(TONE)))
	clock.start(0.0)

	for i in 30:
		await get_tree().process_frame
	var before := clock.get_time_ms()

	clock.set_paused(true)
	_check(clock.is_paused(), "el reloj deberia estar pausado")
	var frozen := clock.get_time_ms()
	for i in 30:
		await get_tree().process_frame
	var still := clock.get_time_ms()
	_check(absf(still - frozen) < 1.0,
		"el reloj avanzo %.1f ms estando en pausa" % (still - frozen))

	clock.set_paused(false)
	var after := clock.get_time_ms()
	_check(absf(after - before) < 60.0,
		"al reanudar el reloj salto %.1f ms" % (after - before))
	for i in 20:
		await get_tree().process_frame
	_check(clock.get_time_ms() > after, "el reloj no volvio a correr tras la pausa")

	print("[pausa] congelado en %.0f ms y reanudado sin salto" % frozen)
	clock.stop()
	clock.queue_free()
