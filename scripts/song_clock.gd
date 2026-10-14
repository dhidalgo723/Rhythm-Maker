class_name SongClock
extends Node

## Fuente de verdad del tiempo de canción.
##
## NUNCA usar _process(delta) acumulado ni get_playback_position() crudo.
## El tiempo audible real es:
##     posicion_mezclada = get_playback_position() + AudioServer.get_time_since_last_mix()
##     tiempo_audible    = posicion_mezclada - AudioServer.get_output_latency()
##
## Sobre esa base se corre un reloj de sistema (Time.get_ticks_usec) anclado y
## corregido por deriva, porque el valor de audio salta en escalones del tamano
## del buffer de mezcla. El reloj de sistema da un valor monotono y suave;
## el reloj de audio evita que se desincronice a largo plazo.
##
## Tempo: con tempo != 1 el tiempo de cancion avanza a `tempo` segundos por
## segundo real. El audio se acelera con pitch_scale y el bus de musica lleva un
## efecto de pitch que deshace el cambio de tono, asi que suena a la misma nota.

## Si audio y sistema difieren mas que esto, re-anclamos de golpe (seek, stutter grave).
const HARD_RESYNC_S := 0.050
## Fraccion del error que se corrige cada frame mientras la diferencia es pequena.
const DRIFT_CORRECTION := 0.08
## Tras un salto, el mezclador tarda un poco en reportar la posicion nueva:
## mientras tanto se ignora el audio para no "corregir" hacia la posicion vieja.
const SEEK_SETTLE_USEC := 150_000

const MUSIC_BUS := "Music"

signal finished()

var player: AudioStreamPlayer

var _running := false
var _paused := false
var _tempo := 1.0
var _anchor_song_s := 0.0     # tiempo de cancion en el instante del ancla
var _anchor_usec := 0         # Time.get_ticks_usec() en el instante del ancla
var _start_offset_s := 0.0    # from_position pasado a play()
var _paused_at_s := 0.0       # tiempo de cancion congelado durante la pausa
var _settle_until_usec := 0


func _init(audio_player: AudioStreamPlayer = null) -> void:
	player = audio_player


func _ready() -> void:
	# El reloj debe actualizarse antes que cualquier consumidor.
	process_priority = -100
	if player == null:
		player = AudioStreamPlayer.new()
		add_child(player)
	player.bus = ensure_music_bus()


## Bus "Music" con un efecto de pitch (desactivado mientras el tempo sea 1).
## Se crea una sola vez y lo comparten todos los relojes.
static func ensure_music_bus() -> StringName:
	if AudioServer.get_bus_index(MUSIC_BUS) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, MUSIC_BUS)
		AudioServer.set_bus_send(idx, &"Master")
		AudioServer.add_bus_effect(idx, AudioEffectPitchShift.new())
		AudioServer.set_bus_effect_enabled(idx, 0, false)
	return StringName(MUSIC_BUS)


func set_stream(stream: AudioStream) -> void:
	stop()
	player.stream = stream


func get_length_ms() -> float:
	if player.stream == null:
		return 0.0
	return player.stream.get_length() * 1000.0


func start(from_ms: float = 0.0) -> void:
	if player.stream == null:
		push_error("SongClock.start() sin stream cargado")
		return
	_start_offset_s = from_ms / 1000.0
	set_tempo(1.0)
	player.play(_start_offset_s)
	# Ancla inicial: el audio todavia no reporta posicion util en el primer frame.
	_anchor_song_s = _start_offset_s
	_anchor_usec = Time.get_ticks_usec()
	_paused = false
	_running = true


func stop() -> void:
	_running = false
	_paused = false
	player.stream_paused = false
	if player.playing:
		player.stop()
	set_music_muted(false)
	_apply_tempo(1.0)


## Congela el reloj y el audio a la vez.
##
## El ancla se lleva contra Time.get_ticks_usec(), que sigue corriendo durante
## la pausa: si no se re-anclara al reanudar, el reloj daria por transcurrido
## todo el rato que el juego estuvo parado y las notas saldrian desplazadas.
func set_paused(value: bool) -> void:
	if not _running or value == _paused:
		return
	_paused = value
	player.stream_paused = value
	if value:
		_paused_at_s = _current_song_s()
	else:
		_reanchor(_paused_at_s)


func is_paused() -> bool:
	return _paused


func is_running() -> bool:
	return _running


func get_tempo() -> float:
	return _tempo


## Cambia la velocidad del audio sin cambiar su tono. 0.75 = 25% mas lento.
func set_tempo(value: float) -> void:
	value = clampf(value, 0.25, 4.0)
	if is_equal_approx(value, _tempo):
		return
	# Re-anclar en el instante del cambio: lo que llevamos se midio con el tempo
	# anterior, lo que viene se mide con el nuevo.
	if _running and not _paused:
		_reanchor(_current_song_s())
	_apply_tempo(value)


## Salta a otro punto de la cancion (adelante o atras).
func seek(to_ms: float) -> void:
	var to_s := clampf(to_ms / 1000.0, 0.0, maxf(get_length_ms() / 1000.0 - 0.05, 0.0))
	if not _running:
		return
	player.seek(to_s)
	if _paused:
		_paused_at_s = to_s
	else:
		_reanchor(to_s)
	_settle_until_usec = Time.get_ticks_usec() + SEEK_SETTLE_USEC


func set_music_muted(value: bool) -> void:
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx != -1:
		AudioServer.set_bus_mute(idx, value)


## Tiempo de canción audible, en ms. Este es el valor que se usa para
## timestamped de inputs, spawn de notas y juicio de hits.
func get_time_ms() -> float:
	if _paused:
		return _paused_at_s * 1000.0
	if not _running:
		return _anchor_song_s * 1000.0
	return _current_song_s() * 1000.0


## Tiempo crudo de audio sin suavizar. Solo para debug/diagnostico de sync.
func get_raw_audio_time_ms() -> float:
	if player.stream == null or not player.playing:
		return 0.0
	return _raw_audio_time_s() * 1000.0


func _current_song_s() -> float:
	var elapsed := float(Time.get_ticks_usec() - _anchor_usec) / 1_000_000.0
	return _anchor_song_s + elapsed * _tempo


func _reanchor(song_s: float) -> void:
	_anchor_song_s = song_s
	_anchor_usec = Time.get_ticks_usec()


func _apply_tempo(value: float) -> void:
	_tempo = value
	if player != null:
		player.pitch_scale = value
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx != -1 and AudioServer.get_bus_effect_count(idx) > 0:
		var shift := AudioServer.get_bus_effect(idx, 0) as AudioEffectPitchShift
		if shift != null:
			shift.pitch_scale = 1.0 / value
		AudioServer.set_bus_effect_enabled(idx, 0, not is_equal_approx(value, 1.0))


func _raw_audio_time_s() -> float:
	# Lo que mide el mezclador esta en tiempo real; a tempo != 1 cada segundo
	# real son `tempo` segundos de cancion.
	var real_offset := AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	return player.get_playback_position() + real_offset * _tempo


func _process(_delta: float) -> void:
	if not _running or _paused:
		return

	if not player.playing:
		_running = false
		finished.emit()
		return

	var now_usec := Time.get_ticks_usec()
	if now_usec < _settle_until_usec:
		return

	var audio_s := _raw_audio_time_s()
	# Los primeros frames el mixer aun no arranco: playback_position ~0 y el
	# valor compensado puede salir negativo. Ignorar hasta que sea valido.
	if audio_s <= _start_offset_s:
		return

	var sys_s := _current_song_s()
	var error := audio_s - sys_s

	if absf(error) > HARD_RESYNC_S:
		_reanchor(audio_s)
	else:
		_anchor_song_s += error * DRIFT_CORRECTION
