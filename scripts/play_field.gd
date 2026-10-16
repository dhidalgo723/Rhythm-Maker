class_name PlayField
extends Control

## Dibuja los carriles, los receptores y las notas cayendo de arriba a abajo.
## Todo en un solo _draw() para no crear/destruir nodos por nota.
##
## Las teclas salen del atlas de pixel art (KeyIcons). Si no esta, se dibujan
## formas geometricas de reserva para que el juego siga siendo jugable.
##
## Los efectos visuales de los jefes (inversion, pista ondulada, zoom, pista
## invertida, notas camufladas, fantasma...) se leen de las reglas del
## PlaybackManager: este nodo solo dibuja, nunca decide.

## Factor de escala del pixel art: celdas de 16 px -> 112 px. Entero, para que
## cada pixel del sprite ocupe un bloque exacto y no quede borroso ni irregular.
const SCALE := 7
const CELL_PX := KeyIcons.CELL * SCALE
const LANE_W := float(CELL_PX)
const LANE_GAP := 10.0
const TOP_MARGIN := 84.0   # por debajo del HUD y la barra de progreso
const RECEPTOR_MARGIN := 120.0

## Las notas aparecen con un fundido muy corto arriba del todo, para que no
## "salten" a la vista pero sean legibles casi desde que entran.
const FADE_IN_PORTION := 0.04
## Cuanto mezclar el color del carril sobre las teclas claras. Poco: el sprite
## ya dice la direccion, el color solo ayuda a distinguir carriles de reojo.
const NOTE_TINT := 0.45

## Destello del receptor al acertar, en segundos.
const HIT_FLASH_S := 0.14

## Parte final del recorrido en la que las notas fantasma / malditas no se ven.
const GHOST_PORTION := 0.28
## Ancho de la cola de una nota larga.
const HOLD_TAIL_W := 26.0
## Notas senuelo: rojas.
const DECOY_TINT := Color(1.0, 0.28, 0.28)
## Pista Ondulada: amplitud en px, longitud de onda en px y velocidad.
const WAVE_AMP := 46.0
const WAVE_LENGTH := 260.0
const WAVE_SPEED := 2.4
## Zoom de Camara: cuanto se acerca en cada beat.
const ZOOM_AMP := 0.07
## Rapidez con que se suavizan los cambios (velocidad, posicion de carriles).
const SMOOTHING := 7.0

# --- Reserva sin atlas ---
const FALLBACK_SIZE := 92.0
## Angulo de rotacion de la flecha por id de carril (el espacio no rota).
const LANE_ANGLE: Array[float] = [-PI / 2.0, PI, 0.0, PI / 2.0, 0.0]
## Flecha apuntando hacia arriba, en espacio unitario centrado en el origen.
const ARROW_POLY: Array[Vector2] = [
	Vector2(0.0, -0.5), Vector2(0.5, 0.0), Vector2(0.24, 0.0),
	Vector2(0.24, 0.5), Vector2(-0.24, 0.5), Vector2(-0.24, 0.0),
	Vector2(-0.5, 0.0),
]

var manager: PlaybackManager

var _held := PackedByteArray()
var _flash := PackedFloat32Array()   # segundos restantes de destello por carril
## Posicion en pantalla (0..COUNT-1) de cada carril, animada: la Inversion
## los desliza en vez de teletransportarlos.
var _slot_pos := PackedFloat32Array()
var _scroll := 1.0
var _use_sprites := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pixel art: con el filtro lineal por defecto los sprites saldrian borrosos.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_use_sprites = KeyIcons.available()
	_held.resize(Lanes.COUNT)
	_flash.resize(Lanes.COUNT)
	_slot_pos.resize(Lanes.COUNT)
	for lane in Lanes.COUNT:
		_slot_pos[lane] = Lanes.display_index(lane)


func bind(pm: PlaybackManager) -> void:
	manager = pm
	pm.lane_pressed.connect(func(l: int) -> void: _held[l] = 1)
	pm.lane_released.connect(func(l: int) -> void: _held[l] = 0)
	pm.note_hit.connect(func(l: int, _k: Judgement.Kind, _d: float) -> void:
		_flash[l] = HIT_FLASH_S)


func _process(delta: float) -> void:
	for i in Lanes.COUNT:
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - delta)

	var k := 1.0 - exp(-delta * SMOOTHING)
	var t := _time()
	for lane in Lanes.COUNT:
		_slot_pos[lane] = lerpf(_slot_pos[lane], _target_slot(lane, t), k)
	var target_scroll := manager.scroll_multiplier(t) if _playing() else 1.0
	_scroll = lerpf(_scroll, target_scroll, k)
	queue_redraw()


func receptor_y() -> float:
	return size.y - RECEPTOR_MARGIN


## Centro horizontal de un carril (por id), segun su posicion en pantalla.
func lane_x(lane: int) -> float:
	var total := Lanes.COUNT * LANE_W + (Lanes.COUNT - 1) * LANE_GAP
	return (size.x - total) * 0.5 + _slot_pos[lane] * (LANE_W + LANE_GAP) + LANE_W * 0.5


func _playing() -> bool:
	return manager != null and manager.is_active()


func _time() -> float:
	return manager.get_time_ms() if _playing() else 0.0


func _rules() -> PlayRules:
	return manager.rules if manager != null else null


## Inversion: izquierda y derecha intercambian su sitio en pantalla.
func _target_slot(lane: int, t: float) -> float:
	var slot := Lanes.display_index(lane)
	if _playing() and manager.is_effect_active(TimedEffect.INVERT, t):
		var left := Lanes.display_index(0)
		var right := Lanes.display_index(3)
		if lane == 0:
			slot = right
		elif lane == 3:
			slot = left
	return slot


func _draw() -> void:
	var t := _time()
	var rules := _rules()
	var reversed := _playing() and manager.is_effect_active(TimedEffect.REVERSE, t)

	# Zoom de Camara: late con el beat, centrado en la pantalla.
	if _playing() and rules.zoom:
		var s := 1.0 + ZOOM_AMP * _beat_pulse(t)
		var pivot := size * 0.5
		draw_set_transform(pivot * (1.0 - s), 0.0, Vector2(s, s))

	# Pista Invertida: receptores arriba y las notas suben desde abajo.
	var rec_y := TOP_MARGIN + CELL_PX * 0.5 if reversed else receptor_y()
	var spawn_y := size.y - 10.0 if reversed else TOP_MARGIN
	var travel_px := spawn_y - rec_y   # negativo en normal: las notas bajan

	# Columnas de fondo, con un toque del color del carril.
	for lane in Lanes.DISPLAY_ORDER:
		var cx := lane_x(lane)
		var alpha := 0.015 if _disabled(lane) else 0.05
		draw_rect(Rect2(cx - LANE_W * 0.5, 0.0, LANE_W, size.y), Color(Lanes.COLORS[lane], alpha))

	# Receptores: hundidos y apagados en reposo, encendidos al pulsar.
	for lane in Lanes.DISPLAY_ORDER:
		var center := Vector2(_wave_x(lane, rec_y, t), rec_y)
		if _disabled(lane):
			_draw_key(center, lane, KeyIcons.Variant.PRESSED, false, Color(1, 1, 1, 0.22))
			_draw_cross(center)
		elif _flash[lane] > 0.0:
			_draw_key(center, lane, KeyIcons.Variant.PRESSED_OUTLINE, true, _tint(lane))
		elif _held[lane] == 1:
			_draw_key(center, lane, KeyIcons.Variant.PRESSED, true, _tint(lane))
		else:
			_draw_key(center, lane, KeyIcons.Variant.PRESSED, false, Color(1, 1, 1, 0.75))

	if not _playing():
		return

	var base_travel := manager.rules.travel_time_ms if manager.rules.travel_time_ms > 0 \
		else Settings.travel_time_ms
	var travel := float(base_travel) / maxf(_scroll, 0.05)
	for lane in Lanes.DISPLAY_ORDER:
		var notes := manager.lane_notes(lane)
		var i := manager.lane_head(lane)
		while i < notes.size():
			var pn: PlayNote = notes[i]
			i += 1
			if not pn.is_live():
				continue
			var progress := (float(pn.time_ms) - t) / travel
			if progress > 1.0:
				break   # las siguientes estan aun mas lejos
			if pn.state == PlayNote.State.HOLDING:
				progress = 0.0   # la cabeza se queda en el receptor mientras se mantiene
			if progress < -0.25:
				continue
			_draw_note(pn, progress, rec_y, travel_px, travel, t)


func _draw_note(pn: PlayNote, progress: float, rec_y: float, travel_px: float,
		travel: float, t: float) -> void:
	var lane := pn.lane
	# Teclas Mezcladas: cae por otra columna, pero con el icono y el color de
	# su carril, que es la tecla que hay que pulsar.
	var column := pn.note.show_lane if pn.note.show_lane >= 0 else lane
	var rules := _rules()
	var y := rec_y + progress * travel_px
	var alpha := clampf((1.0 - progress) / FADE_IN_PORTION, 0.0, 1.0)

	# Notas Fantasma / Flecha Maldita: desaparecen el ultimo tramo.
	var hidden: bool = (rules.ghost or lane in rules.cursed_lanes) \
		and progress < GHOST_PORTION and pn.state != PlayNote.State.HOLDING
	if hidden:
		return

	var color := DECOY_TINT if pn.note.decoy else _tint(lane)
	color.a = alpha

	if pn.note.is_hold():
		var end_progress := (float(pn.note.end_ms()) - t) / travel
		var end_y := rec_y + clampf(end_progress, 0.0, 1.0) * travel_px
		var x := _wave_x(column, y, t)
		var top := minf(y, end_y)
		var tail := Color(Lanes.COLORS[lane], 0.55 * alpha)
		draw_rect(Rect2(x - HOLD_TAIL_W * 0.5, top, HOLD_TAIL_W, absf(end_y - y)), tail)

	var center := Vector2(_wave_x(column, y, t), y)
	if rules.camouflage and not pn.note.decoy:
		_draw_plain_key(center, alpha)
		return
	# Doble golpe: contorno blanco hasta el primer golpe.
	var variant := KeyIcons.Variant.OUTLINE if pn.note.hits > 1 and pn.hits_done == 0 \
		else KeyIcons.Variant.NORMAL
	_draw_key(center, lane, variant, true, color)


func _disabled(lane: int) -> bool:
	var rules := _rules()
	return rules != null and lane in rules.disabled_lanes


## Pista Ondulada: desplazamiento horizontal segun la altura.
func _wave_x(lane: int, y: float, t: float) -> float:
	var x := lane_x(lane)
	var rules := _rules()
	if rules != null and rules.wave and _playing():
		x += WAVE_AMP * sin(y / WAVE_LENGTH * TAU + t / 1000.0 * WAVE_SPEED)
	return x


## 1 justo en el beat, cayendo a 0 hasta el siguiente.
func _beat_pulse(t: float) -> float:
	var beat := manager.chart.beat_ms() if manager.chart != null else 0.0
	if beat <= 0.0:
		beat = 500.0   # 120 BPM si el chart no lo sabe
	var phase := fposmod(t - float(manager.chart.beat_offset_ms), beat) / beat
	return pow(1.0 - phase, 3.0)


func _tint(lane: int) -> Color:
	return Color.WHITE.lerp(Lanes.COLORS[lane], NOTE_TINT)


func _draw_key(center: Vector2, lane: int, variant: KeyIcons.Variant, light: bool,
		modulate_color: Color) -> void:
	if _use_sprites:
		var tex := KeyIcons.texture(lane, variant, light)
		# Redondear: un sprite a media posicion de pixel tiembla al caer.
		var top_left := (center - Vector2(CELL_PX, CELL_PX) * 0.5).round()
		draw_texture_rect(tex, Rect2(top_left, Vector2(CELL_PX, CELL_PX)), false, modulate_color)
		return

	# Reserva sin atlas: flecha o barra de color.
	var lit := variant != KeyIcons.Variant.PRESSED or light
	var c := Lanes.COLORS[lane] if lit else Color(Lanes.COLORS[lane], 0.3)
	c = Color(c.r * modulate_color.r, c.g * modulate_color.g, c.b * modulate_color.b, c.a * modulate_color.a)
	if lane == Lanes.SPACE:
		var r := Rect2(center - Vector2(FALLBACK_SIZE * 0.6, FALLBACK_SIZE * 0.22),
			Vector2(FALLBACK_SIZE * 1.2, FALLBACK_SIZE * 0.44))
		draw_rect(r, c)
		draw_rect(r, Color(0, 0, 0, c.a * 0.55), false, 2.0)
	else:
		var pts := _arrow_points(center, FALLBACK_SIZE, lane)
		draw_colored_polygon(pts, c)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, c.a * 0.55), 2.0)


## Notas Camufladas: todas iguales, gris y sin flecha. Se dibuja con bloques
## del tamano del pixel del sprite para no desentonar.
func _draw_plain_key(center: Vector2, alpha: float) -> void:
	var w := 9.0 * SCALE
	var h := 11.0 * SCALE
	var top_left := (center - Vector2(w, h) * 0.5).round()
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0.08, 0.07, 0.12, alpha))
	draw_rect(Rect2(top_left + Vector2(SCALE, SCALE), Vector2(w - 2 * SCALE, h - 3 * SCALE)),
		Color(0.62, 0.64, 0.74, alpha))
	draw_rect(Rect2(top_left + Vector2(SCALE, h - 2 * SCALE), Vector2(w - 2 * SCALE, SCALE)),
		Color(0.36, 0.38, 0.5, alpha))


## Carril desactivado: aspa roja sobre el receptor.
func _draw_cross(center: Vector2) -> void:
	var r := CELL_PX * 0.3
	var c := Color(0.95, 0.25, 0.25, 0.8)
	draw_line(center + Vector2(-r, -r), center + Vector2(r, r), c, 6.0)
	draw_line(center + Vector2(-r, r), center + Vector2(r, -r), c, 6.0)


func _arrow_points(center: Vector2, px: float, lane: int) -> PackedVector2Array:
	var a := LANE_ANGLE[lane]
	var cos_a := cos(a)
	var sin_a := sin(a)
	var pts := PackedVector2Array()
	for p in ARROW_POLY:
		var v := p * px
		pts.append(center + Vector2(v.x * cos_a - v.y * sin_a, v.x * sin_a + v.y * cos_a))
	return pts
