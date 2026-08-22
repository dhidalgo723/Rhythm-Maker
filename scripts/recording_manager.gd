class_name RecordingManager
extends Node

## Fase 2: reproduce la cancion y captura inputs con timestamp compensado.

## Dos pulsaciones en el mismo lane separadas por menos de esto se consideran
## rebote de tecla y la segunda se descarta.
const MIN_GAP_MS := 40

signal note_recorded(note: ChartNote)
signal lane_pressed(lane: int)
signal lane_released(lane: int)
signal recording_finished(chart: Chart)

var clock: SongClock
var chart: Chart

var _recording := false
var _last_time_per_lane := PackedFloat32Array()


func _ready() -> void:
	clock = SongClock.new()
	add_child(clock)
	clock.finished.connect(_on_song_finished)
	set_process_unhandled_input(false)


func start(stream: AudioStream, song_file: String) -> void:
	chart = Chart.new()
	chart.song_path = song_file.get_file()
	chart.offset_ms = Settings.offset_ms

	_last_time_per_lane = PackedFloat32Array()
	_last_time_per_lane.resize(Lanes.COUNT)
	_last_time_per_lane.fill(-99999.0)

	clock.set_stream(stream)
	clock.start(0.0)
	_recording = true
	set_process_unhandled_input(true)


func stop() -> void:
	if not _recording:
		return
	_recording = false
	set_process_unhandled_input(false)
	clock.stop()
	chart.sort_notes()
	recording_finished.emit(chart)


func is_recording() -> bool:
	return _recording


func get_time_ms() -> float:
	return clock.get_time_ms()


func _unhandled_input(event: InputEvent) -> void:
	if not _recording:
		return

	var released := Lanes.lane_released(event)
	if released != -1:
		lane_released.emit(released)
		return

	var lane := Lanes.lane_pressed(event)
	if lane == -1:
		return

	get_viewport().set_input_as_handled()
	lane_pressed.emit(lane)

	# El input se timestamped en el momento en que llega, con el reloj de audio
	# compensado, menos el offset de calibracion del usuario (que llega tarde).
	var t := clock.get_time_ms() - float(Settings.offset_ms)
	if t < 0.0:
		return
	if t - _last_time_per_lane[lane] < MIN_GAP_MS:
		return

	_last_time_per_lane[lane] = t
	var note := ChartNote.new(roundi(t), lane)
	chart.notes.append(note)
	note_recorded.emit(note)


func _on_song_finished() -> void:
	stop()
