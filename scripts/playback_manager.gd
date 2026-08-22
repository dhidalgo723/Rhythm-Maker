class_name PlaybackManager
extends Node

## Fase 4: reproduce el chart, juzga los inputs y lleva el score.
##
## Las notas se consumen en orden dentro de cada lane, asi que basta un puntero
## de cabeza por lane en vez de marcar nota por nota.

signal note_hit(lane: int, kind: Judgement.Kind, delta_ms: float)
signal note_missed(lane: int)
signal lane_pressed(lane: int)
signal lane_released(lane: int)
signal score_changed(score: int, combo: int, misses: int)
signal song_ended()
signal game_over()

var clock: SongClock
var chart: Chart

var score := 0
var combo := 0
var max_combo := 0
var misses := 0
var perfects := 0
var goods := 0

## Notas por lane y puntero a la siguiente sin juzgar.
var _lane_notes: Array[Array] = []
var _lane_head := PackedInt32Array()
var _active := false
var _finished := false


func _ready() -> void:
	clock = SongClock.new()
	add_child(clock)
	clock.finished.connect(_on_song_finished)
	set_process_unhandled_input(false)


func start(stream: AudioStream, song_chart: Chart) -> void:
	chart = song_chart
	chart.sort_notes()

	_lane_notes = []
	for i in Lanes.COUNT:
		_lane_notes.append([])
	for n in chart.notes:
		if n.lane >= 0 and n.lane < Lanes.COUNT:
			_lane_notes[n.lane].append(n)

	_lane_head = PackedInt32Array()
	_lane_head.resize(Lanes.COUNT)
	_lane_head.fill(0)

	score = 0
	combo = 0
	max_combo = 0
	misses = 0
	perfects = 0
	goods = 0
	_finished = false
	_active = true

	clock.set_stream(stream)
	clock.start(0.0)
	set_process_unhandled_input(true)
	score_changed.emit(score, combo, misses)


func stop() -> void:
	_active = false
	set_process_unhandled_input(false)
	clock.stop()


func is_active() -> bool:
	return _active


## Tiempo de juego: reloj de audio compensado menos el offset del usuario.
## Misma convencion que en grabacion, para que grabar y jugar sean simetricos.
func get_time_ms() -> float:
	return clock.get_time_ms() - float(Settings.offset_ms)


## Notas de un lane (para dibujar) y desde que indice siguen vivas.
func lane_notes(lane: int) -> Array:
	return _lane_notes[lane]


func lane_head(lane: int) -> int:
	return _lane_head[lane]


func total_notes() -> int:
	return chart.notes.size() if chart != null else 0


func accuracy() -> float:
	var judged := perfects + goods + misses
	if judged == 0:
		return 0.0
	return float(perfects * 100 + goods * 60) / float(judged * 100) * 100.0


func _process(_delta: float) -> void:
	if not _active:
		return

	# Notas que ya pasaron la ventana de acierto sin que nadie las tocara.
	var t := get_time_ms()
	var deadline := t - Judgement.GOOD_MS
	for lane in Lanes.COUNT:
		var notes: Array = _lane_notes[lane]
		while _lane_head[lane] < notes.size() \
				and (notes[_lane_head[lane]] as ChartNote).timestamp_ms < deadline:
			_lane_head[lane] += 1
			_register_miss(lane)
			if not _active:
				return


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
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

	var t := get_time_ms()
	var notes: Array = _lane_notes[lane]
	var head: int = _lane_head[lane]

	if head < notes.size():
		var note: ChartNote = notes[head]
		var delta := t - float(note.timestamp_ms)
		var kind := Judgement.classify(delta)
		if kind != Judgement.Kind.MISS:
			_lane_head[lane] += 1
			_register_hit(lane, kind, delta)
			return

	# Tecla pulsada sin ninguna nota en ventana: tambien penaliza.
	_register_miss(lane)


func _register_hit(lane: int, kind: Judgement.Kind, delta: float) -> void:
	if kind == Judgement.Kind.PERFECT:
		perfects += 1
	else:
		goods += 1
	score = maxi(0, score + Judgement.score_for(kind, combo))
	combo += 1
	max_combo = maxi(max_combo, combo)
	note_hit.emit(lane, kind, delta)
	score_changed.emit(score, combo, misses)


func _register_miss(lane: int) -> void:
	misses += 1
	combo = 0
	score = maxi(0, score + Judgement.SCORE_MISS)
	note_missed.emit(lane)
	score_changed.emit(score, combo, misses)

	if misses > Judgement.MAX_MISSES:
		_finish(true)


func _on_song_finished() -> void:
	# Deja que las ultimas notas terminen de juzgarse antes de cerrar.
	await get_tree().create_timer(Judgement.GOOD_MS / 1000.0).timeout
	_finish(false)


func _finish(lost: bool) -> void:
	if _finished:
		return
	_finished = true
	stop()
	if lost:
		game_over.emit()
	else:
		song_ended.emit()
