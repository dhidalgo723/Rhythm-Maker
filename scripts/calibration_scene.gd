extends Control

## Pantalla de calibracion de latencia.

const SETTINGS_SCENE := "res://scenes/settings_scene.tscn"

var _cal: CalibrationManager

var _pulse: Panel
var _instructions: Label
var _progress_label: Label
var _result_label: Label
var _detail_label: Label
var _start_btn: Button
var _save_btn: Button

## Segundos que le quedan al destello del beat.
var _flash := 0.0
var _measured := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

	_cal = CalibrationManager.new()
	add_child(_cal)
	_cal.beat_reached.connect(_on_beat)
	_cal.tap_registered.connect(_on_tap)
	_cal.finished.connect(_on_finished)

	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14101f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	root.add_child(_label("CALIBRACION DE LATENCIA", 32))
	_instructions = _label(
		"Toca ESPACIO (o cualquier flecha del juego) justo cuando oigas cada click.", 15)
	root.add_child(_instructions)
	root.add_child(_label(
		"Los primeros %d clicks son solo para coger el ritmo, no cuentan."
		% CalibrationManager.LEAD_BEATS, 13))
	root.add_child(_spacer(14))

	# Circulo que late con cada beat: referencia visual, pero la buena es el oido.
	var center := CenterContainer.new()
	root.add_child(center)
	_pulse = Panel.new()
	_pulse.custom_minimum_size = Vector2(120, 120)
	center.add_child(_pulse)
	_paint_pulse(false)

	root.add_child(_spacer(10))
	_progress_label = _label("", 20)
	root.add_child(_progress_label)

	_result_label = _label("", 30)
	root.add_child(_result_label)

	_detail_label = _label("", 14)
	_detail_label.modulate = Color(1, 1, 1, 0.6)
	root.add_child(_detail_label)

	root.add_child(_spacer(10))

	_start_btn = _button("EMPEZAR", Vector2(260, 48))
	_start_btn.pressed.connect(_on_start)
	root.add_child(_start_btn)

	_save_btn = _button("GUARDAR OFFSET", Vector2(260, 44))
	_save_btn.pressed.connect(_on_save)
	root.add_child(_save_btn)

	var back := _button("Volver", Vector2(200, 38))
	back.pressed.connect(_go_back)
	root.add_child(back)


static func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func _button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Sin foco: si no, ESPACIO pulsaria el boton en vez de contar como toque.
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	return b


func _paint_pulse(lit: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("ffd23f") if lit else Color("2a2340")
	sb.border_color = Color("ffd23f")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(60)
	_pulse.add_theme_stylebox_override("panel", sb)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		if _flash == 0.0:
			_paint_pulse(false)

	if _cal != null and _cal.is_running():
		_progress_label.text = "Toques: %d   -   click %d de %d" % [
			_cal.taps(), clampi(_cal.current_beat() + 1, 0, _cal.total_beats()),
			_cal.total_beats()]


func _on_beat(_index: int) -> void:
	_flash = 0.12
	_paint_pulse(true)


func _on_tap(delta_ms: float, taps: int) -> void:
	_detail_label.text = "ultimo toque: %+.0f ms   (%d medidos)" % [delta_ms, taps]


func _on_start() -> void:
	_measured = false
	_result_label.text = ""
	_detail_label.text = ""
	_cal.start()
	_refresh()


func _on_finished() -> void:
	_measured = _cal.has_enough_taps()
	if not _measured:
		_result_label.add_theme_color_override("font_color", Color("f9393f"))
		_result_label.text = "Pocos toques (%d de %d minimos)" % [
			_cal.taps(), CalibrationManager.MIN_TAPS]
		_detail_label.text = "Vuelve a intentarlo tocando en cada click."
	else:
		var offset := _cal.offset_ms()
		var spread := _cal.spread_ms()
		_result_label.add_theme_color_override("font_color", Color("2ee6a8"))
		_result_label.text = "Offset medido: %+d ms" % offset
		# Un spread alto significa toques irregulares: la mediana sigue siendo
		# valida pero conviene avisar de que la medida es floja.
		var quality := "buena" if spread < 25.0 else "irregular, repite para afinar"
		_detail_label.text = "%d toques   -   variacion +-%.0f ms   -   medida %s" % [
			_cal.taps(), spread, quality]
	_progress_label.text = ""
	_refresh()


func _on_save() -> void:
	if not _measured:
		return
	Settings.offset_ms = _cal.offset_ms()
	Settings.save_settings()
	_detail_label.text = "Guardado. Se aplicara al grabar y al jugar."
	_save_btn.disabled = true


func _refresh() -> void:
	var running := _cal != null and _cal.is_running()
	_start_btn.disabled = running
	_start_btn.text = "REPETIR" if _measured else "EMPEZAR"
	_save_btn.disabled = not _measured
	_instructions.visible = not _measured


func _go_back() -> void:
	if _cal != null:
		_cal.stop()
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()
