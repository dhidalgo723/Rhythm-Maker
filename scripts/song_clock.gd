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

## Si audio y sistema difieren mas que esto, re-anclamos de golpe (seek, stutter grave).
const HARD_RESYNC_S := 0.050
## Fraccion del error que se corrige cada frame mientras la diferencia es pequena.
const DRIFT_CORRECTION := 0.08

signal finished()

var player: AudioStreamPlayer

var _running := false
var _anchor_song_s := 0.0     # tiempo de cancion en el instante del ancla
var _anchor_usec := 0         # Time.get_ticks_usec() en el instante del ancla
var _start_offset_s := 0.0    # from_position pasado a play()


func _init(audio_player: AudioStreamPlayer = null) -> void:
	player = audio_player


func _ready() -> void:
	# El reloj debe actualizarse antes que cualquier consumidor.
	process_priority = -100
	if player == null:
		player = AudioStreamPlayer.new()
		add_child(player)


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
	player.play(_start_offset_s)
	# Ancla inicial: el audio todavia no reporta posicion util en el primer frame.
	_anchor_song_s = _start_offset_s
	_anchor_usec = Time.get_ticks_usec()
	_running = true


func stop() -> void:
	_running = false
	if player.playing:
		player.stop()


func is_running() -> bool:
	return _running


## Tiempo de canción audible, en ms. Este es el valor que se usa para
## timestamped de inputs, spawn de notas y juicio de hits.
func get_time_ms() -> float:
	if not _running:
		return _anchor_song_s * 1000.0
	var elapsed := float(Time.get_ticks_usec() - _anchor_usec) / 1_000_000.0
	return (_anchor_song_s + elapsed) * 1000.0


## Tiempo crudo de audio sin suavizar. Solo para debug/diagnostico de sync.
func get_raw_audio_time_ms() -> float:
	if player.stream == null or not player.playing:
		return 0.0
	return _raw_audio_time_s() * 1000.0


func _raw_audio_time_s() -> float:
	var mixed := player.get_playback_position() + AudioServer.get_time_since_last_mix()
	return mixed - AudioServer.get_output_latency()


func _process(_delta: float) -> void:
	if not _running:
		return

	if not player.playing:
		_running = false
		finished.emit()
		return

	var audio_s := _raw_audio_time_s()
	# Los primeros frames el mixer aun no arranco: playback_position ~0 y el
	# valor compensado puede salir negativo. Ignorar hasta que sea valido.
	if audio_s <= _start_offset_s:
		return

	var now_usec := Time.get_ticks_usec()
	var sys_s := _anchor_song_s + float(now_usec - _anchor_usec) / 1_000_000.0
	var error := audio_s - sys_s

	if absf(error) > HARD_RESYNC_S:
		_anchor_song_s = audio_s
		_anchor_usec = now_usec
	else:
		_anchor_song_s += error * DRIFT_CORRECTION
