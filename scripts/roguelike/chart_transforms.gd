class_name ChartTransforms
extends RefCounted

## Cambios que hacen los jefes a las notas de una cancion. Siempre sobre una
## COPIA del chart (Chart.duplicate_chart) y con un RandomNumberGenerator con
## semilla, para que la misma partida genere siempre el mismo jefe.

## Separacion minima entre un senuelo y cualquier nota de su carril: si
## estuvieran mas cerca no se sabria cual se pretendia pulsar.
const DECOY_GAP_MS := 350
## Dos notas a menos de esto se consideran a la vez (un acorde).
const SAME_TIME_MS := 30
## Notas Pegajosas: margen hasta la siguiente nota del carril y limites.
const STICKY_GAP_MS := 150
const STICKY_MIN_MS := 250
const STICKY_MAX_MS := 1500


## Tramo aleatorio de `fraction` de la cancion, lejos del principio y del final.
static func random_segment(rng: RandomNumberGenerator, length_ms: float, fraction: float) -> Vector2:
	var span := length_ms * fraction
	var lo := length_ms * 0.1
	var hi := maxf(lo, length_ms * 0.9 - span)
	var start := rng.randf_range(lo, hi)
	return Vector2(start, start + span)


static func real_notes(chart: Chart) -> Array[ChartNote]:
	var out: Array[ChartNote] = []
	for n in chart.notes:
		if not n.decoy:
			out.append(n)
	return out


## Doble Golpe: una parte de las notas sueltas pide 2 pulsaciones.
static func double_hits(chart: Chart, rng: RandomNumberGenerator, fraction: float) -> int:
	var candidates: Array[ChartNote] = []
	for n in chart.notes:
		if not n.decoy and not n.is_hold():
			candidates.append(n)
	var picked := _pick(candidates, roundi(candidates.size() * fraction), rng)
	for n in picked:
		n.hits = 2
	return picked.size()


## Notas Senuelo: anade senuelos en huecos libres. Devuelve cuantos anadio.
static func add_decoys(chart: Chart, rng: RandomNumberGenerator, fraction: float,
		from_ms: float = 0.0, to_ms: float = INF) -> int:
	var real := real_notes(chart)
	if real.is_empty():
		return 0
	var lo := maxf(from_ms, float(real[0].timestamp_ms))
	var hi := minf(to_ms, float(real[-1].timestamp_ms))
	var wanted := roundi(real.size() * fraction)
	var added := 0
	var attempts := wanted * 30
	while added < wanted and attempts > 0:
		attempts -= 1
		var t := roundi(rng.randf_range(lo, hi))
		var lane := rng.randi_range(0, Lanes.COUNT - 1)
		if _lane_busy(chart, lane, t, DECOY_GAP_MS):
			continue
		var n := chart.add_note(t, lane)
		n.decoy = true
		added += 1
	chart.sort_notes()
	return added


## Cuerda Rota: un carril de direccion deja de funcionar y sus notas se
## reparten entre los demas. Devuelve el carril roto.
static func break_string(chart: Chart, rng: RandomNumberGenerator) -> int:
	var dirs := Settings.DIRECTION_LANES
	var broken: int = dirs[rng.randi_range(0, dirs.size() - 1)]
	var others: Array[int] = []
	for lane in Lanes.COUNT:
		if lane != broken:
			others.append(lane)

	var turn := rng.randi_range(0, others.size() - 1)
	var keep: Array[ChartNote] = []
	var moved: Array[ChartNote] = []
	for n in chart.notes:
		if n.lane != broken:
			keep.append(n)
		else:
			moved.append(n)
	chart.notes = keep
	for n in moved:
		# Siguiente carril libre en ese instante; si todos estan ocupados, la
		# nota se pierde (ya habia un acorde de 4).
		for attempt in others.size():
			var target := others[(turn + attempt) % others.size()]
			if not _lane_busy(chart, target, n.timestamp_ms, SAME_TIME_MS, n.duration_ms):
				n.lane = target
				chart.notes.append(n)
				break
		turn += 1
	chart.sort_notes()
	return broken


## Polirritmia: las notas de un carril se desplazan a tresillos (la rejilla de
## un tercio de beat que NO coincide con negras), contra el resto que sigue en
## negras y corcheas. Necesita bpm; si no lo hay devuelve -1 y no cambia nada.
static func polyrhythm(chart: Chart, rng: RandomNumberGenerator) -> int:
	var beat := chart.beat_ms()
	if beat <= 0.0:
		return -1
	var dirs := Settings.DIRECTION_LANES
	var lane: int = dirs[rng.randi_range(0, dirs.size() - 1)]
	var third := beat / 3.0
	var origin := float(chart.beat_offset_ms)
	var used := {}
	var keep: Array[ChartNote] = []
	for n in chart.notes:
		if n.lane != lane or n.decoy or n.is_hold():
			keep.append(n)
			continue
		var exact := (n.timestamp_ms - origin) / third
		var k := roundi(exact)
		if k % 3 == 0:
			k += 1 if exact >= k else -1
		var t := roundi(origin + k * third)
		if used.has(t) or t < 0:
			continue   # dos notas fueron al mismo tresillo: sobra una
		used[t] = true
		n.timestamp_ms = t
		keep.append(n)
	chart.notes = keep
	chart.sort_notes()
	return lane


## Notas Pegajosas: en el tramo, las notas del carril con mas notas se
## convierten en largas que duran hasta poco antes de su siguiente nota.
static func sticky_notes(chart: Chart, from_ms: float, to_ms: float) -> int:
	var lane := busiest_lane(chart, from_ms, to_ms)
	if lane == -1:
		return -1
	var lane_notes: Array[ChartNote] = []
	for n in chart.notes:
		if n.lane == lane and not n.decoy:
			lane_notes.append(n)
	for i in lane_notes.size():
		var n := lane_notes[i]
		if n.timestamp_ms < from_ms or n.timestamp_ms >= to_ms or n.is_hold():
			continue
		var limit := STICKY_MAX_MS
		if i + 1 < lane_notes.size():
			limit = mini(limit, lane_notes[i + 1].timestamp_ms - n.timestamp_ms - STICKY_GAP_MS)
		if limit >= STICKY_MIN_MS:
			n.duration_ms = limit
			n.hits = 1
	return lane


## Rasgueo: cada nota larga de al menos `min_ms` se parte en 2 o 3 trozos
## seguidos, con `gap_ms` de hueco entre uno y otro. Devuelve cuantas se partieron.
static func strum(chart: Chart, rng: RandomNumberGenerator, min_ms: int, gap_ms: int) -> int:
	var out: Array[ChartNote] = []
	var split := 0
	for n in chart.notes:
		if n.decoy or n.duration_ms < min_ms:
			out.append(n)
			continue
		# Cada trozo, al menos tan largo como el hueco: si no caben 3, van 2.
		var pieces := rng.randi_range(2, 3)
		if n.duration_ms < pieces * gap_ms + (pieces - 1) * gap_ms:
			pieces = 2
		var piece := (n.duration_ms - gap_ms * (pieces - 1)) / pieces
		for i in pieces:
			var part := n.copy()
			part.timestamp_ms = n.timestamp_ms + i * (piece + gap_ms)
			part.duration_ms = piece
			part.hits = 1
			out.append(part)
		split += 1
	chart.notes = out
	chart.sort_notes()
	return split


## Teclas Mezcladas: en el tramo, cada nota cae por otra columna (se sigue
## tocando con la tecla de su carril). Las que caen a la vez van por columnas
## distintas, y nunca por una ocupada aun por una nota larga, para que no se
## monten. Devuelve cuantas cambiaron de columna.
static func shuffle_columns(chart: Chart, from_ms: float, to_ms: float, rng: RandomNumberGenerator,
		avoid: Array[int]) -> int:
	var columns: Array[int] = []
	for lane in Lanes.DISPLAY_ORDER:
		if not lane in avoid:
			columns.append(lane)
	var busy_until := {}   # columna -> ms en que acaba la larga que cae por ella
	var used_at := {}      # columna -> instante de la ultima nota que cayo por ella
	var moved := 0
	for n in chart.notes:
		if n.timestamp_ms < from_ms or n.timestamp_ms >= to_ms:
			continue
		var free: Array[int] = []
		for c in columns:
			var taken_now: bool = used_at.has(c) and absi(int(used_at[c]) - n.timestamp_ms) <= SAME_TIME_MS
			if c != n.lane and not taken_now and int(busy_until.get(c, -1)) < n.timestamp_ms:
				free.append(c)
		if free.is_empty():
			continue
		var c := free[rng.randi_range(0, free.size() - 1)]
		n.show_lane = c
		used_at[c] = n.timestamp_ms
		busy_until[c] = n.end_ms() + STICKY_GAP_MS if n.is_hold() else -1
		moved += 1
	return moved


## Carril Minado: en el tramo, todas las notas de un carril pasan a senuelos.
static func minefield(chart: Chart, from_ms: float, to_ms: float) -> int:
	var lane := busiest_lane(chart, from_ms, to_ms)
	if lane == -1:
		return -1
	for n in chart.notes:
		if n.lane == lane and n.timestamp_ms >= from_ms and n.timestamp_ms < to_ms:
			n.decoy = true
			n.duration_ms = 0
			n.hits = 1
	return lane


## Carril de direccion con mas notas reales en un tramo, o -1.
static func busiest_lane(chart: Chart, from_ms: float, to_ms: float) -> int:
	var counts := {}
	for n in chart.notes:
		if n.decoy or not n.lane in Settings.DIRECTION_LANES:
			continue
		if n.timestamp_ms >= from_ms and n.timestamp_ms < to_ms:
			counts[n.lane] = int(counts.get(n.lane, 0)) + 1
	var best := -1
	for lane in counts:
		if best == -1 or counts[lane] > counts[best]:
			best = lane
	return best


## Hay alguna nota en el carril a menos de `gap` de `t` (o una larga que lo cubre)?
static func _lane_busy(chart: Chart, lane: int, t: int, gap: int, duration: int = 0) -> bool:
	for n in chart.notes:
		if n.lane != lane:
			continue
		var start := n.timestamp_ms - gap
		var end := n.end_ms() + gap
		if t + duration >= start and t <= end:
			return true
	return false


## `count` elementos al azar sin repetir.
static func _pick(items: Array[ChartNote], count: int, rng: RandomNumberGenerator) -> Array[ChartNote]:
	var pool := items.duplicate()
	var out: Array[ChartNote] = []
	while out.size() < count and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out
