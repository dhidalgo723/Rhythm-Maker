extends Control

## Pantalla de calibracion de latencia.

const SETTINGS_SCENE := "res://scenes/settings_scene.tscn"
## 16 px de la bolita x 7: escala entera, el pixel art no se deforma.
const PULSE_PX := 112

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
	_start_btn.grab_focus.call_deferred()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = GuiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := _label(Lang.t("CALIBRACIÓN DE LATENCIA"), 32)
	title.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
	root.add_child(title)
	_instructions = _label(
		Lang.t("Toca ESPACIO (o cualquier flecha del juego) justo cuando oigas cada click."), 15)
	root.add_child(_instructions)
	root.add_child(_label(
		Lang.t("Los primeros %d clicks son solo para coger el ritmo, no cuentan.")
		% CalibrationManager.LEAD_BEATS, 13))
	root.add_child(_spacer(14))

	# Circulo que late con cada beat: referencia visual, pero la buena es el oido.
	var center := CenterContainer.new()
	root.add_child(center)
	# Piloto del aparato: apagado en reposo, se enciende en amarillo con cada
	# click. Se dibuja en vez de sacarlo del atlas: las bolitas del atlas miden
	# 11 px y a este tamano saldrian borrosas.
	_pulse = Panel.new()
	_pulse.custom_minimum_size = Vector2(PULSE_PX, PULSE_PX)
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

	_start_btn = _button(Lang.t("EMPEZAR"), Vector2(280, 52))
	_start_btn.theme_type_variation = "BigButton"
	_start_btn.pressed.connect(_on_start)
	root.add_child(_start_btn)

	_save_btn = _button(Lang.t("GUARDAR OFFSET"), Vector2(280, 52))
	_save_btn.theme_type_variation = "BigButton"
	_save_btn.pressed.connect(_on_save)
	root.add_child(_save_btn)

	var back := _button(Lang.t("Volver"), Vector2(200, 38))
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
	b.add_theme_font_size_override("font_size", 18)
	return b


func _paint_pulse(lit: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GuiTheme.TEXT_FOCUS if lit else GuiTheme.BODY_DARK
	sb.border_color = GuiTheme.BODY_LIGHT
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(PULSE_PX / 2)
	if lit:
		sb.shadow_color = Color(GuiTheme.TEXT_FOCUS, 0.45)
		sb.shadow_size = 18
	_pulse.add_theme_stylebox_override("panel", sb)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		if _flash == 0.0:
			_paint_pulse(false)

	if _cal != null and _cal.is_running():
		_progress_label.text = Lang.t("Toques: %d   -   click %d de %d") % [
			_cal.taps(), clampi(_cal.current_beat() + 1, 0, _cal.total_beats()),
			_cal.total_beats()]


func _on_beat(_index: int) -> void:
	_flash = 0.12
	_paint_pulse(true)


func _on_tap(delta_ms: float, taps: int) -> void:
	_detail_label.text = Lang.t("último toque: %+.0f ms   (%d medidos)") % [delta_ms, taps]


func _on_start() -> void:
	_measured = false
	_result_label.text = ""
	_detail_label.text = ""
	_cal.start()
	# Mientras se mide no puede haber nada con foco: ESPACIO y las flechas son
	# los toques, y un boton con foco se los quedaria (ESPACIO lo pulsaria).
	get_viewport().gui_release_focus()
	_refresh()


func _on_finished() -> void:
	_measured = _cal.has_enough_taps()
	if not _measured:
		_result_label.add_theme_color_override("font_color", Color("f9393f"))
		_result_label.text = Lang.t("Pocos toques (%d de %d mínimos)") % [
			_cal.taps(), CalibrationManager.MIN_TAPS]
		_detail_label.text = Lang.t("Vuelve a intentarlo tocando en cada click.")
	else:
		var offset := _cal.offset_ms()
		var spread := _cal.spread_ms()
		_result_label.add_theme_color_override("font_color", Color("2ee6a8"))
		_result_label.text = Lang.t("Offset medido: %+d ms") % offset
		# Un spread alto significa toques irregulares: la mediana sigue siendo
		# valida pero conviene avisar de que la medida es floja.
		var quality := Lang.t("buena") if spread < 25.0 else Lang.t("irregular, repite para afinar")
		_detail_label.text = Lang.t("%d toques   -   variación +-%.0f ms   -   medida %s") % [
			_cal.taps(), spread, quality]
	_progress_label.text = ""
	_refresh()
	# Se espera un poco antes de devolver el foco: el jugador puede dar un par
	# de toques de mas al acabar y no deben pulsar un boton por accidente.
	await get_tree().create_timer(0.6).timeout
	if is_inside_tree() and not _cal.is_running():
		(_save_btn if _measured else _start_btn).grab_focus()


func _on_save() -> void:
	if not _measured:
		return
	Settings.offset_ms = _cal.offset_ms()
	Settings.save_settings()
	_detail_label.text = Lang.t("Guardado. Se aplicará al grabar y al jugar.")
	_save_btn.disabled = true


func _refresh() -> void:
	var running := _cal != null and _cal.is_running()
	_start_btn.disabled = running
	_start_btn.text = Lang.t("REPETIR") if _measured else Lang.t("EMPEZAR")
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
