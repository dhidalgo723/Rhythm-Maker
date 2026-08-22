class_name CalibrationManager
extends Node

## Fase 3: mide cuanto se retrasan los toques del jugador respecto al audio que
## oye, y lo deja en Settings.offset_ms.
##
## Reproduce un metronomo con el mismo SongClock que usa el juego y compara cada
## toque con el beat mas cercano. El resultado incluye TODO lo que hay en medio:
## latencia de salida, buffer del sistema, bluetooth y el tiempo de reaccion del
## jugador. Por eso se aplica igual al grabar que al jugar, y ambos modos quedan
## simetricos.

const BPM := 100.0
## Beats de entrada que no se miden: hacen falta un par para coger el ritmo.
const LEAD_BEATS := 4
const MEASURED_BEATS := 16
## Por debajo de esto la mediana no es fiable y no se ofrece guardar.
const MIN_TAPS := 6

## Cada toque se atribuye al beat mas cercano, asi que el desfase medido nunca
## pasa de medio beat por construccion. Se descarta antes de eso, al 40%: un
## toque tan lejos de cualquier click es un fallo del jugador, no su latencia
## (y una latencia real de 240 ms a 100 BPM no se podria distinguir del beat
## siguiente de todos modos).
const MAX_ABS_DELTA_MS := 60000.0 / BPM * 0.4

signal beat_reached(index: int)
signal tap_registered(delta_ms: float, taps: int)
signal finished()

var clock: SongClock
## Desfases medidos, en ms. Positivo = el jugador toca TARDE.
var deltas: Array[float] = []

var _running := false
var _last_beat := -1


func _ready() -> void:
	clock = SongClock.new()
	add_child(clock)
	clock.finished.connect(_on_stream_finished)
	set_process_unhandled_input(false)


func total_beats() -> int:
	return LEAD_BEATS + MEASURED_BEATS


func start() -> void:
	deltas.clear()
	_last_beat = -1
	_running = true
	clock.set_stream(Metronome.make_stream(BPM, total_beats()))
	clock.start(0.0)
	set_process_unhandled_input(true)


func stop() -> void:
	if not _running:
		return
	_running = false
	set_process_unhandled_input(false)
	clock.stop()
	finished.emit()


func is_running() -> bool:
	return _running


func beat_ms() -> float:
	return 60000.0 / BPM


## Beat que esta sonando ahora mismo (puede ser negativo antes del primero).
func current_beat() -> int:
	return int(floorf(clock.get_time_ms() / beat_ms()))


func taps() -> int:
	return deltas.size()


func has_enough_taps() -> bool:
	return deltas.size() >= MIN_TAPS


## Offset a guardar: la mediana, que no se va con un par de toques sueltos como
## haria la media.
func offset_ms() -> int:
	return int(roundf(median(deltas)))


## Cuanto varian los toques entre si. Un valor alto significa que el jugador no
## llevaba bien el ritmo y conviene repetir la medida.
func spread_ms() -> float:
	if deltas.size() < 2:
		return 0.0
	var m := median(deltas)
	var total := 0.0
	for d in deltas:
		total += absf(d - m)
	return total / deltas.size()


func _process(_delta: float) -> void:
	if not _running:
		return
	var beat := current_beat()
	if beat != _last_beat and beat >= 0:
		_last_beat = beat
		beat_reached.emit(beat)


func _unhandled_input(event: InputEvent) -> void:
	if not _running or not event.is_pressed():
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if Lanes.lane_pressed(event) == -1 and not event.is_action_pressed("calibrate_tap"):
		return

	get_viewport().set_input_as_handled()
	register_tap(clock.get_time_ms())


## Separado de _unhandled_input para poder probarlo sin simular eventos.
func register_tap(time_ms: float) -> bool:
	var beat := roundf(time_ms / beat_ms())
	if beat < LEAD_BEATS:
		return false   # todavia en la entrada
	var delta := time_ms - beat * beat_ms()
	if absf(delta) > MAX_ABS_DELTA_MS:
		return false
	deltas.append(delta)
	tap_registered.emit(delta, deltas.size())
	return true


func _on_stream_finished() -> void:
	stop()


static func median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[mid]
	return (sorted[mid - 1] + sorted[mid]) * 0.5
