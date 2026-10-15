class_name PlaybackManager
extends Node

## Reproduce el chart, juzga los inputs y lleva la puntuacion.
##
## Cada nota es un PlayNote con su estado: rebobinar, saltar o quitar notas es
## cambiar estados, sin tocar el chart. Dentro de cada carril las notas se
## juzgan en orden (la mas antigua viva primero), como en cualquier juego de
## ritmo, y `_lane_head` apunta a la primera viva para no recorrer el pasado.
##
## Las reglas especiales (roguelike) llegan en un PlayRules; sin reglas es el
## juego normal.

## Resultados especiales de judge_press, ademas de los Judgement.Kind.
const IGNORED := -1   ## carril desactivado, o pulsar sin consecuencias
const PARTIAL := -2   ## primer golpe de una nota de doble golpe

## Hasta donde llega un toque con Metronomo / Pua / Beat Drop activos: "da igual
## cuando pulses" no puede llegar a notas que aun ni se ven.
const FORCED_REACH_MS := 400.0
## Soltar una nota larga a menos de esto del final cuenta como completa.
const HOLD_RELEASE_TOLERANCE_MS := 150.0
## Tope de velocidad extra que puede acumular el Abucheo.
const MAX_SCROLL_BOOST := 1.0

signal note_hit(lane: int, kind: Judgement.Kind, delta_ms: float)
signal note_missed(lane: int)
signal lane_pressed(lane: int)
signal lane_released(lane: int)
signal score_changed(score: int, combo: int, misses: int)
signal song_ended()
signal game_over()
## Aviso corto para el HUD ("¡Escudo!", "¡Señuelo!"...).
signal message(text: String)
signal hold_completed(lane: int)
signal hold_broken(lane: int)
signal slot_stolen()
signal bis_triggered()
signal keys_rotated(shift: int)

var clock: SongClock
var chart: Chart
var rules := PlayRules.new()

var score := 0
var combo := 0
var max_combo := 0
## Cuantas veces salio cada Judgement.Kind, indexado por el propio Kind.
var counts := PackedInt32Array()
## Fallos que cuentan para el limite. Normalmente = counts[MISS], pero una
## Flecha de Cristal cuenta doble y un Escudo o un rebobinado los quitan.
var misses := 0
## Registro de fallos que cuentan, para poder borrarlos (Cinta de Casete,
## Pedal de Distorsion). Cada entrada: {t, weight, delta, note}.
var miss_log: Array[Dictionary] = []
## Perfectos por carril en carriles con Flecha Hucha.
var coin_perfects := PackedInt32Array()
## Rotacion actual de las flechas (Cambio de Clave).
var key_shift := 0
## Velocidad extra acumulada por el Abucheo.
var scroll_boost := 0.0

var _lane_notes: Array[Array] = []
var _lane_head := PackedInt32Array()
var _real_notes := 0
var _notes_done := 0
var _shield_used := PackedByteArray()
var _consecutive_misses := 0
var _bis_used := false
var _boss_shield_up := false
var _boss_shield_streak := 0
var _boss_shield_down_at := 0.0
var _silenced := false
var _active := false
var _finished := false


func _ready() -> void:
	clock = SongClock.new()
	add_child(clock)
	clock.finished.connect(_on_song_finished)
	set_process_unhandled_input(false)


func start(stream: AudioStream, song_chart: Chart, play_rules: PlayRules = null) -> void:
	chart = song_chart
	chart.sort_notes()
	rules = play_rules if play_rules != null else PlayRules.new()

	_lane_notes = []
	for i in Lanes.COUNT:
		_lane_notes.append([])
	_real_notes = 0
	for n in chart.notes:
		if n.lane < 0 or n.lane >= Lanes.COUNT:
			continue
		if n.lane in rules.disabled_lanes:
			continue
		_lane_notes[n.lane].append(PlayNote.new(n))
		if not n.decoy:
			_real_notes += 1

	_lane_head = PackedInt32Array()
	_lane_head.resize(Lanes.COUNT)
	_shield_used = PackedByteArray()
	_shield_used.resize(Lanes.COUNT)
	coin_perfects = PackedInt32Array()
	coin_perfects.resize(Lanes.COUNT)

	score = 0
	combo = 0
	max_combo = 0
	misses = 0
	miss_log.clear()
	counts = PackedInt32Array()
	counts.resize(Judgement.Kind.size())
	key_shift = 0
	scroll_boost = 0.0
	_notes_done = 0
	_consecutive_misses = 0
	_bis_used = false
	_boss_shield_up = rules.boss_shield_perfects > 0
	_boss_shield_streak = 0
	_silenced = false
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


## Duracion jugable: hasta chart.end_ms si lo hay, si no hasta el final del audio.
func song_length_ms() -> float:
	var audio := clock.get_length_ms()
	if chart != null and chart.end_ms > 0:
		return minf(float(chart.end_ms), audio) if audio > 0.0 else float(chart.end_ms)
	return audio


## 0..1: cuanto de la cancion ha pasado.
func song_progress(t_ms: float) -> float:
	var length := song_length_ms()
	return clampf(t_ms / length, 0.0, 1.0) if length > 0.0 else 0.0


# --- Consultas para dibujar y para la interfaz ---

## Notas (PlayNote) de un carril, y desde que indice siguen vivas.
func lane_notes(lane: int) -> Array:
	return _lane_notes[lane]


func lane_head(lane: int) -> int:
	return _lane_head[lane]


## Notas reales (sin senuelos) de la partida.
func total_notes() -> int:
	return _real_notes


func count(kind: Judgement.Kind) -> int:
	return counts[kind] if not counts.is_empty() else 0


## Notas acertadas, sea con el nivel que sea.
func hits() -> int:
	return judged() - count(Judgement.Kind.MISS)


func judged() -> int:
	var total := 0
	for c in counts:
		total += c
	return total


## Precision en %: cada nivel pesa segun Judgement.ACCURACY.
func accuracy() -> float:
	if judged() == 0:
		return 0.0
	var weighted := 0.0
	for kind in Judgement.ORDER:
		weighted += counts[kind] * float(Judgement.ACCURACY[kind])
	return weighted / judged() * 100.0


func boss_shield_up() -> bool:
	return _boss_shield_up


func bis_used() -> bool:
	return _bis_used


# --- Efectos con tramo ---

func add_effect(id: String, from_ms: float, to_ms: float, data: Dictionary = {}) -> TimedEffect:
	return rules.add_effect(id, from_ms, to_ms, data)


func is_effect_active(id: String, t_ms: float) -> bool:
	for e in rules.effects:
		if e.id == id and e.is_active(t_ms):
			return true
	return false


func active_effect(id: String, t_ms: float) -> TimedEffect:
	for e in rules.effects:
		if e.id == id and e.is_active(t_ms):
			return e
	return null


## Multiplicador de la velocidad de caida (>1 = las notas caen mas rapido).
func scroll_multiplier(t_ms: float) -> float:
	var m := 1.0
	if not is_equal_approx(rules.crescendo_to, 1.0):
		m *= lerpf(1.0, rules.crescendo_to, song_progress(t_ms))
	m *= 1.0 + scroll_boost
	for e in rules.effects:
		if e.id == TimedEffect.SCROLL and e.is_active(t_ms):
			m *= float(e.data.get("mult", 1.0))
	return m


## Carril al que va una tecla con la rotacion de Cambio de Clave aplicada.
func remap_lane(lane: int) -> int:
	if key_shift == 0 or not lane in Settings.DIRECTION_LANES:
		return lane
	var dirs := Settings.DIRECTION_LANES
	return dirs[(dirs.find(lane) + key_shift) % dirs.size()]


# --- Bucle ---

func _process(_delta: float) -> void:
	if not _active:
		return
	var t := get_time_ms()
	_update_audio_effects(t)
	_update_boss_shield(t)

	for lane in Lanes.COUNT:
		_sweep_lane(lane, t)
		if not _active:
			return

	var length := song_length_ms()
	if length > 0.0 and t >= length + Judgement.HIT_WINDOW_MS:
		_finish(false)


## Lo que ya paso la ventana sin que nadie lo tocara: fallo (o nada, si es un
## senuelo). Las notas largas mantenidas se completan al llegar a su final.
func _sweep_lane(lane: int, t: float) -> void:
	var notes: Array = _lane_notes[lane]
	var deadline := t - _late_reach(lane, t)
	var i := _lane_head[lane]
	while i < notes.size():
		var pn: PlayNote = notes[i]
		if pn.state == PlayNote.State.HOLDING:
			if t >= pn.note.end_ms():
				_complete_hold(pn)
			else:
				break   # una larga mantenida ocupa el carril hasta que acaba
		elif pn.state == PlayNote.State.PENDING:
			if pn.time_ms >= deadline:
				break
			if pn.note.decoy:
				pn.state = PlayNote.State.SKIPPED
			else:
				pn.state = PlayNote.State.MISSED
				_register_miss(lane, pn, pn.time_ms)
				if not _active:
					return
		i += 1
	_advance_head(lane)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or clock.is_paused():
		return

	var released := Lanes.lane_released(event)
	if released != -1:
		var lane_r := remap_lane(released)
		lane_released.emit(lane_r)
		judge_release(lane_r, get_time_ms())
		return

	var pressed := Lanes.lane_pressed(event)
	if pressed == -1:
		return

	get_viewport().set_input_as_handled()
	var lane := remap_lane(pressed)
	lane_pressed.emit(lane)
	judge_press(lane, get_time_ms())


## Juzga un toque en un carril en un instante de cancion dado. Separado de
## _unhandled_input para poder probar cada caso sin depender del framerate.
## Devuelve un Judgement.Kind, o IGNORED / PARTIAL.
func judge_press(lane: int, time_ms: float) -> int:
	if lane in rules.disabled_lanes:
		return IGNORED

	# Beat Drop: cualquier tecla acierta la nota mas cercana de cualquier carril.
	if is_effect_active(TimedEffect.ANY_KEY_PERFECT, time_ms):
		var any := _earliest_live_any_lane(time_ms, FORCED_REACH_MS)
		if any == null:
			return IGNORED
		_hit(any, Judgement.Kind.PERFECT, time_ms - any.time_ms, time_ms)
		return Judgement.Kind.PERFECT

	var forced := -1
	var reach := _late_reach(lane, time_ms)
	if is_effect_active(TimedEffect.ALWAYS_PERFECT, time_ms):
		forced = Judgement.Kind.PERFECT
	elif is_effect_active(TimedEffect.ALWAYS_GOOD, time_ms):
		forced = Judgement.Kind.GOOD

	var pn := _earliest_live(lane, time_ms, reach)
	if pn == null:
		# Volver a pulsar mientras se mantiene una larga no es un fallo.
		if _holding(lane) != null:
			return IGNORED
		_register_miss(lane, null, time_ms)
		return Judgement.Kind.MISS

	if pn.note.decoy:
		pn.state = PlayNote.State.SKIPPED
		_advance_head(lane)
		message.emit(Lang.t("¡Señuelo!"))
		_register_miss(lane, null, time_ms)
		return Judgement.Kind.MISS

	var delta := time_ms - float(pn.time_ms)
	var kind: int = forced
	if kind == -1:
		kind = Judgement.classify_with(delta, _window_mult(lane, time_ms), rules.perfect_window_mult)
	if kind == Judgement.Kind.MISS:
		_register_miss(lane, null, time_ms)
		return Judgement.Kind.MISS

	if pn.note.hits > 1 and pn.hits_done + 1 < pn.note.hits:
		pn.hits_done += 1
		return PARTIAL

	_hit(pn, kind, delta, time_ms)
	return kind


## Soltar una tecla: solo importa si habia una nota larga mantenida.
func judge_release(lane: int, time_ms: float) -> void:
	var pn := _holding(lane)
	if pn == null:
		return
	if time_ms >= pn.note.end_ms() - HOLD_RELEASE_TOLERANCE_MS:
		_complete_hold(pn)
	elif is_effect_active(TimedEffect.SUSTAIN, time_ms) or lane in rules.unbreakable_hold_lanes:
		message.emit(Lang.t("Sustain"))
		_complete_hold(pn)
	else:
		pn.state = PlayNote.State.MISSED
		message.emit(Lang.t("¡Rota!"))
		hold_broken.emit(lane)
		_register_miss(lane, pn, time_ms)
	_advance_head(lane)


# --- Saltos en el tiempo (mejoras) ---

## Vuelve atras `ms` y borra los fallos de ese tramo; esas notas vuelven a
## estar vivas. Lo acertado sigue acertado. (Cinta de Casete)
func rewind(ms: float) -> int:
	var t := get_time_ms()
	var from := maxf(0.0, t - ms)
	var erased := erase_misses_since(from)
	for lane in Lanes.COUNT:
		for pn: PlayNote in _lane_notes[lane]:
			if pn.state == PlayNote.State.HOLDING:
				pn.state = PlayNote.State.HIT
	_recompute_heads()
	clock.seek(from + float(Settings.offset_ms))
	return erased


## Borra los fallos registrados desde `from_ms`. Devuelve cuantos borro.
func erase_misses_since(from_ms: float) -> int:
	var erased := 0
	for i in range(miss_log.size() - 1, -1, -1):
		var entry: Dictionary = miss_log[i]
		if float(entry["t"]) < from_ms:
			continue
		_undo_miss(entry)
		miss_log.remove_at(i)
		erased += 1
	_recompute_heads()
	score_changed.emit(score, combo, misses)
	return erased


## Borra TODOS los fallos de la cancion (Pedal de Distorsion).
func erase_all_misses() -> int:
	return erase_misses_since(-INF)


## Avanza `ms`; lo que se salta no cuenta ni como acierto ni como fallo.
func skip(ms: float) -> void:
	var t := get_time_ms()
	var to := minf(t + ms, song_length_ms() - 500.0)
	if to <= t:
		return
	# Un poco de margen: lo que cae justo al aterrizar tampoco debe castigar.
	var limit := to + Judgement.HIT_WINDOW_MS
	for lane in Lanes.COUNT:
		for pn: PlayNote in _lane_notes[lane]:
			if pn.state == PlayNote.State.HOLDING:
				pn.state = PlayNote.State.HIT
			elif pn.state == PlayNote.State.PENDING and pn.time_ms <= limit:
				pn.state = PlayNote.State.SKIPPED
	_recompute_heads()
	clock.seek(to + float(Settings.offset_ms))


## Quita sin penalizar las notas vivas de un tramo que cumplan `filter`
## (Arreglo Simplificado). Devuelve cuantas quito.
func skip_notes(from_ms: float, to_ms: float, filter: Callable) -> int:
	var removed := 0
	for lane in Lanes.COUNT:
		for pn: PlayNote in _lane_notes[lane]:
			if pn.state == PlayNote.State.PENDING and pn.time_ms >= from_ms \
					and pn.time_ms < to_ms and filter.call(pn):
				pn.state = PlayNote.State.SKIPPED
				removed += 1
		_advance_head(lane)
	return removed


## Mueve las notas vivas de un tramo a otro carril (Pad de DJ). Si en el destino
## ya hay una nota a la vez, la movida se quita en vez de duplicarla.
func move_notes_to_lane(from_ms: float, to_ms: float, target: int) -> int:
	var moved := 0
	var taken := {}
	for pn: PlayNote in _lane_notes[target]:
		if pn.is_live():
			taken[pn.time_ms] = true
	for lane in Lanes.COUNT:
		if lane == target:
			continue
		var keep: Array = []
		for pn: PlayNote in _lane_notes[lane]:
			var inside: bool = pn.state == PlayNote.State.PENDING and not pn.note.decoy \
				and pn.time_ms >= from_ms and pn.time_ms < to_ms
			if not inside:
				keep.append(pn)
				continue
			if taken.has(pn.time_ms):
				pn.state = PlayNote.State.SKIPPED
				keep.append(pn)
				continue
			var copy := pn.note.copy()
			copy.lane = target
			var moved_note := PlayNote.new(copy)
			moved_note.hits_done = pn.hits_done
			_lane_notes[target].append(moved_note)
			taken[pn.time_ms] = true
			moved += 1
		_lane_notes[lane] = keep
	_lane_notes[target].sort_custom(func(a: PlayNote, b: PlayNote) -> bool:
		return a.time_ms < b.time_ms)
	_recompute_heads()
	return moved


# --- Internos ---

func _window_mult(lane: int, t_ms: float) -> float:
	var m := rules.lane_window_mult[lane]
	if is_effect_active(TimedEffect.WINDOW_X2, t_ms):
		m *= 2.0
	return m


## Lo mas tarde que se puede pulsar una nota y que aun cuente.
func _late_reach(lane: int, t_ms: float) -> float:
	var reach := Judgement.BAD_MS * _window_mult(lane, t_ms)
	if is_effect_active(TimedEffect.ALWAYS_PERFECT, t_ms) \
			or is_effect_active(TimedEffect.ALWAYS_GOOD, t_ms) \
			or is_effect_active(TimedEffect.ANY_KEY_PERFECT, t_ms):
		reach = maxf(reach, FORCED_REACH_MS)
	return reach


func _earliest_live(lane: int, t_ms: float, reach: float) -> PlayNote:
	var notes: Array = _lane_notes[lane]
	for i in range(_lane_head[lane], notes.size()):
		var pn: PlayNote = notes[i]
		if pn.time_ms > t_ms + reach:
			return null
		if pn.state == PlayNote.State.PENDING and absf(pn.time_ms - t_ms) <= reach:
			return pn
	return null


func _earliest_live_any_lane(t_ms: float, reach: float) -> PlayNote:
	var best: PlayNote = null
	for lane in Lanes.COUNT:
		var pn := _earliest_live(lane, t_ms, reach)
		if pn != null and not pn.note.decoy and (best == null or pn.time_ms < best.time_ms):
			best = pn
	return best


func _holding(lane: int) -> PlayNote:
	var notes: Array = _lane_notes[lane]
	var head := _lane_head[lane]
	if head < notes.size() and (notes[head] as PlayNote).state == PlayNote.State.HOLDING:
		return notes[head]
	return null


func _hit(pn: PlayNote, kind: int, delta: float, t_ms: float) -> void:
	var lane := pn.lane
	counts[kind] += 1

	var points := int(round(Judgement.score_for(kind, combo) * rules.lane_score_mult[lane]))
	if _boss_shield_up:
		points = 0
		_boss_shield_streak = _boss_shield_streak + 1 if kind == Judgement.Kind.PERFECT else 0
		if _boss_shield_streak >= rules.boss_shield_perfects:
			_boss_shield_up = false
			_boss_shield_down_at = t_ms
			message.emit(Lang.t("¡Escudo del jefe roto!"))
	score += points
	pn.score_delta = points

	combo += 1
	max_combo = maxi(max_combo, combo)
	_consecutive_misses = 0
	if kind == Judgement.Kind.PERFECT and lane in rules.coin_lanes:
		coin_perfects[lane] += 1

	pn.state = PlayNote.State.HOLDING if pn.note.is_hold() else PlayNote.State.HIT
	_advance_head(lane)
	_note_done()
	note_hit.emit(lane, kind, delta)
	score_changed.emit(score, combo, misses)


func _complete_hold(pn: PlayNote) -> void:
	pn.state = PlayNote.State.HIT
	var bonus := 0 if _boss_shield_up else \
		int(round(Judgement.HOLD_BONUS * rules.lane_score_mult[pn.lane]))
	score += bonus
	pn.score_delta += bonus
	_advance_head(pn.lane)
	hold_completed.emit(pn.lane)
	score_changed.emit(score, combo, misses)


## `pn` = la nota fallada, o null si fue un toque sin nota (o un senuelo).
func _register_miss(lane: int, pn: PlayNote, t_ms: float) -> void:
	# Ensayo: se ve el fallo pero no cuenta.
	if t_ms < rules.risk_free_until_ms:
		note_missed.emit(lane)
		return
	# Flecha Escudo: el primer fallo de la cancion en ese carril no cuenta.
	if lane in rules.shield_lanes and _shield_used[lane] == 0:
		_shield_used[lane] = 1
		message.emit(Lang.t("¡Escudo!"))
		return

	var weight := rules.lane_miss_weight[lane]
	counts[Judgement.Kind.MISS] += 1
	misses += weight
	var before := score
	score = maxi(0, score + Judgement.score_for(Judgement.Kind.MISS, 0))
	var delta := score - before
	if pn != null:
		pn.score_delta += delta
		_note_done()
	miss_log.append({"t": t_ms, "weight": weight, "delta": delta, "note": pn})

	combo = 0
	_boss_shield_streak = 0
	_consecutive_misses += 1
	if rules.steal_after_misses > 0 and _consecutive_misses >= rules.steal_after_misses:
		_consecutive_misses = 0
		slot_stolen.emit()
	scroll_boost = minf(scroll_boost + rules.scroll_per_miss, MAX_SCROLL_BOOST)

	note_missed.emit(lane)
	score_changed.emit(score, combo, misses)

	if misses > rules.miss_limit:
		if rules.bis and not _bis_used:
			_bis_used = true
			misses = rules.miss_limit
			message.emit(Lang.t("¡Bis!"))
			bis_triggered.emit()
			score_changed.emit(score, combo, misses)
		else:
			_finish(true)


func _undo_miss(entry: Dictionary) -> void:
	misses = maxi(0, misses - int(entry["weight"]))
	counts[Judgement.Kind.MISS] = maxi(0, counts[Judgement.Kind.MISS] - 1)
	score = maxi(0, score - int(entry["delta"]))
	var pn: PlayNote = entry["note"]
	if pn != null:
		pn.state = PlayNote.State.PENDING
		pn.hits_done = 0
		pn.score_delta -= int(entry["delta"])


## Cambio de Clave: rota las flechas cada N notas juzgadas.
func _note_done() -> void:
	_notes_done += 1
	if rules.key_rotation_every > 0 and _notes_done % rules.key_rotation_every == 0:
		key_shift = (key_shift + 1) % Settings.DIRECTION_LANES.size()
		message.emit(Lang.t("¡Cambio de clave!"))
		keys_rotated.emit(key_shift)


func _update_boss_shield(t_ms: float) -> void:
	if rules.boss_shield_perfects <= 0 or _boss_shield_up:
		return
	if t_ms - _boss_shield_down_at >= rules.boss_shield_regen_ms:
		_boss_shield_up = true
		_boss_shield_streak = 0
		message.emit(Lang.t("El escudo del jefe se regenera"))


## Tempo y silencio son efectos del audio: se aplican al reloj aqui, en un
## solo sitio, para que dos efectos a la vez se combinen bien.
func _update_audio_effects(t_ms: float) -> void:
	var tempo := 1.0
	var silent := false
	for e in rules.effects:
		if not e.is_active(t_ms):
			continue
		if e.id == TimedEffect.TEMPO:
			tempo *= float(e.data.get("tempo", 1.0))
		elif e.id == TimedEffect.SILENCE:
			silent = true
	if not is_equal_approx(tempo, clock.get_tempo()):
		clock.set_tempo(tempo)
	if silent != _silenced:
		_silenced = silent
		clock.set_music_muted(silent)


func _advance_head(lane: int) -> void:
	var notes: Array = _lane_notes[lane]
	var i := _lane_head[lane]
	while i < notes.size() and not (notes[i] as PlayNote).is_live():
		i += 1
	_lane_head[lane] = i


func _recompute_heads() -> void:
	for lane in Lanes.COUNT:
		_lane_head[lane] = 0
		_advance_head(lane)


func _on_song_finished() -> void:
	# Deja que las ultimas notas terminen de juzgarse antes de cerrar.
	await get_tree().create_timer(Judgement.HIT_WINDOW_MS / 1000.0).timeout
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
