class_name PlayField
extends Control

## Dibuja los carriles, los receptores y las notas cayendo de arriba a abajo.
## Todo en un solo _draw() para no crear/destruir nodos por nota.

const LANE_W := 110.0
const LANE_GAP := 16.0
const NOTE_SIZE := 92.0
const TOP_MARGIN := 50.0
const RECEPTOR_MARGIN := 150.0

## Angulo de rotacion de la flecha por lane: izq, abajo, arriba, der.
const LANE_ANGLE: Array[float] = [-PI / 2.0, PI, 0.0, PI / 2.0]

## Flecha apuntando hacia arriba, en espacio unitario centrado en el origen.
const ARROW_POLY: Array[Vector2] = [
	Vector2(0.0, -0.5), Vector2(0.5, 0.0), Vector2(0.24, 0.0),
	Vector2(0.24, 0.5), Vector2(-0.24, 0.5), Vector2(-0.24, 0.0),
	Vector2(-0.5, 0.0),
]

var manager: PlaybackManager

var _held := PackedByteArray()
var _flash := PackedFloat32Array()   # segundos restantes de brillo por lane


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held.resize(Lanes.COUNT)
	_flash.resize(Lanes.COUNT)


func bind(pm: PlaybackManager) -> void:
	manager = pm
	pm.lane_pressed.connect(func(l: int) -> void: _held[l] = 1)
	pm.lane_released.connect(func(l: int) -> void: _held[l] = 0)
	pm.note_hit.connect(func(l: int, _k: Judgement.Kind, _d: float) -> void: _flash[l] = 0.18)


func _process(delta: float) -> void:
	for i in Lanes.COUNT:
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - delta)
	queue_redraw()


func receptor_y() -> float:
	return size.y - RECEPTOR_MARGIN


func lane_x(lane: int) -> float:
	var total := Lanes.COUNT * LANE_W + (Lanes.COUNT - 1) * LANE_GAP
	return (size.x - total) * 0.5 + lane * (LANE_W + LANE_GAP) + LANE_W * 0.5


func _draw() -> void:
	var rec_y := receptor_y()
	var travel_px := rec_y - TOP_MARGIN

	# Columnas de fondo.
	for lane in Lanes.COUNT:
		var cx := lane_x(lane)
		draw_rect(Rect2(cx - LANE_W * 0.5, 0.0, LANE_W, size.y), Color(1, 1, 1, 0.035))

	# Receptores.
	for lane in Lanes.COUNT:
		var c: Color = Lanes.COLORS[lane]
		var lit := _held[lane] == 1 or _flash[lane] > 0.0
		var center := Vector2(lane_x(lane), rec_y)
		if lit:
			_draw_arrow(center, NOTE_SIZE * 1.06, c, lane, true)
		else:
			_draw_arrow(center, NOTE_SIZE, Color(c, 0.22), lane, true)
			_draw_arrow_outline(center, NOTE_SIZE, Color(c, 0.85), lane, 3.0)

	if manager == null or not manager.is_active():
		return

	var t := manager.get_time_ms()
	var travel := float(Settings.travel_time_ms)

	for lane in Lanes.COUNT:
		var notes := manager.lane_notes(lane)
		var i := manager.lane_head(lane)
		while i < notes.size():
			var note: ChartNote = notes[i]
			var progress := (float(note.timestamp_ms) - t) / travel
			if progress > 1.0:
				break   # las siguientes estan aun mas lejos
			if progress >= -0.25:
				var y := rec_y - progress * travel_px
				# Aparecen con fade en la parte alta para que no "salten".
				var alpha := clampf(inverse_lerp(1.0, 0.9, progress), 0.0, 1.0)
				_draw_arrow(Vector2(lane_x(lane), y), NOTE_SIZE,
					Color(Lanes.COLORS[lane], alpha), lane, true)
			i += 1


func _arrow_points(center: Vector2, px: float, lane: int) -> PackedVector2Array:
	var a := LANE_ANGLE[lane]
	var cos_a := cos(a)
	var sin_a := sin(a)
	var pts := PackedVector2Array()
	for p in ARROW_POLY:
		var v := p * px
		pts.append(center + Vector2(v.x * cos_a - v.y * sin_a, v.x * sin_a + v.y * cos_a))
	return pts


func _draw_arrow(center: Vector2, px: float, color: Color, lane: int, _filled: bool) -> void:
	var pts := _arrow_points(center, px, lane)
	draw_colored_polygon(pts, color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, color.a * 0.55), 2.0)


func _draw_arrow_outline(center: Vector2, px: float, color: Color, lane: int, width: float) -> void:
	var pts := _arrow_points(center, px, lane)
	draw_polyline(pts + PackedVector2Array([pts[0]]), color, width)
