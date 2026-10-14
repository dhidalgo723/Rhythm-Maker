extends Control

## Pantalla de Ajustes: reasignar las teclas de los cuatro carriles.
## Cada carril tiene dos: principal y secundaria (esta puede quedar vacia).

const MENU_SCENE := "res://scenes/main_menu.tscn"
const CALIBRATION_SCENE := "res://scenes/calibration_scene.tscn"
const KEY_BTN_SIZE := Vector2(150, 36)
## Separacion entre botones de una misma fila: lo que ocupa el cursor de
## seleccion, para que no tape el boton de al lado.
const NAV_GAP := 22

## _key_buttons[slot][lane] y _clear_buttons[lane], indexados por id de carril
## (no por fila: las filas siguen el orden de pantalla, con el espacio en medio).
var _key_buttons: Array[Array] = []
var _clear_buttons: Array[Button] = []
var _preset_labels: Array[Label] = []
var _offset_label: Label
var _status: Label

## Hueco que espera una tecla, o -1 si no estamos reasignando.
var _waiting_slot := -1
var _waiting_lane := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = GuiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title := _center_label("AJUSTES", 34)
	title.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
	root.add_child(title)
	root.add_child(_center_label("Teclas del juego", 19))
	root.add_child(_center_label(
		"Pulsa un hueco y despues la tecla que quieras. Esc cancela.", 13))
	root.add_child(_spacer(2))
	root.add_child(_build_grid())
	root.add_child(_spacer(4))

	for slot in Settings.SLOT_COUNT:
		root.add_child(_build_preset_row(slot))

	root.add_child(_spacer(4))
	root.add_child(_build_latency_row())

	root.add_child(_spacer(0))
	_status = _center_label("", 15)
	root.add_child(_status)

	var back := Button.new()
	back.text = "Volver"
	back.custom_minimum_size = Vector2(200, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_go_back)
	root.add_child(back)

	_refresh()
	# Empezar sobre la primera tecla: lo mas probable es venir a cambiarla.
	(_key_buttons[Settings.SLOT_PRIMARY][Lanes.DISPLAY_ORDER[0]] as Button).grab_focus.call_deferred()


func _build_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", NAV_GAP)
	grid.add_theme_constant_override("v_separation", 4)

	# Cabecera: hueco para la flecha y el nombre, luego un titulo por slot.
	grid.add_child(Control.new())
	grid.add_child(Control.new())
	for slot in Settings.SLOT_COUNT:
		var header := _center_label(Settings.SLOT_NAMES[slot], 14)
		header.custom_minimum_size = Vector2(KEY_BTN_SIZE.x, 0)
		header.modulate = Color(1, 1, 1, 0.6)
		grid.add_child(header)
	grid.add_child(Control.new())

	_key_buttons.resize(Settings.SLOT_COUNT)
	for slot in Settings.SLOT_COUNT:
		var row_buttons: Array[Button] = []
		row_buttons.resize(Lanes.COUNT)
		_key_buttons[slot] = row_buttons
	_clear_buttons.resize(Lanes.COUNT)

	for lane in Lanes.DISPLAY_ORDER:
		grid.add_child(KeyIcons.make_icon(lane, 32))

		var lane_name := Label.new()
		lane_name.text = Lanes.NAMES[lane]
		lane_name.custom_minimum_size = Vector2(120, 0)
		grid.add_child(lane_name)

		for slot in Settings.SLOT_COUNT:
			var btn := Button.new()
			btn.custom_minimum_size = KEY_BTN_SIZE
			btn.add_theme_font_size_override("font_size", 17)
			btn.pressed.connect(_on_rebind.bind(slot, lane))
			grid.add_child(btn)
			_key_buttons[slot][lane] = btn

		var clear := Button.new()
		clear.text = "X"
		clear.custom_minimum_size = Vector2(40, KEY_BTN_SIZE.y)
		clear.tooltip_text = "Quitar la tecla secundaria"
		clear.pressed.connect(_on_clear.bind(lane))
		grid.add_child(clear)
		_clear_buttons[lane] = clear

	return grid


func _build_preset_row(slot: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", NAV_GAP)

	var label := Label.new()
	label.text = "%s:" % Settings.SLOT_NAMES[slot]
	label.custom_minimum_size = Vector2(110, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	for preset_name in Settings.PRESETS:
		var b := Button.new()
		b.text = preset_name
		b.custom_minimum_size = Vector2(96, 34)
		b.pressed.connect(_on_preset.bind(slot, preset_name))
		row.add_child(b)

	# Solo la secundaria puede quedarse sin teclas.
	if slot == Settings.SLOT_SECONDARY:
		var none := Button.new()
		none.text = "Ninguna"
		none.custom_minimum_size = Vector2(96, 34)
		none.pressed.connect(_on_preset.bind(slot, ""))
		row.add_child(none)

	var current := _center_label("", 13)
	current.custom_minimum_size = Vector2(150, 0)
	current.modulate = Color(1, 1, 1, 0.55)
	row.add_child(current)
	_preset_labels.append(current)

	return row


func _build_latency_row() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_center_label("Latencia", 19))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", NAV_GAP)
	box.add_child(row)

	var minus := Button.new()
	minus.text = "-5 ms"
	minus.custom_minimum_size = Vector2(80, 34)
	minus.pressed.connect(_nudge_offset.bind(-5))
	row.add_child(minus)

	_offset_label = _center_label("", 17)
	_offset_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(_offset_label)

	var plus := Button.new()
	plus.text = "+5 ms"
	plus.custom_minimum_size = Vector2(80, 34)
	plus.pressed.connect(_nudge_offset.bind(5))
	row.add_child(plus)

	var calibrate := Button.new()
	calibrate.text = "Calibrar..."
	calibrate.custom_minimum_size = Vector2(120, 34)
	calibrate.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(CALIBRATION_SCENE))
	row.add_child(calibrate)

	return box


func _nudge_offset(amount: int) -> void:
	_cancel_wait()
	Settings.offset_ms = clampi(Settings.offset_ms + amount, -500, 500)
	Settings.save_settings()
	_set_status("Offset: %+d ms" % Settings.offset_ms, Color("2ee6a8"))
	_refresh()


static func _center_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	return l


static func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _refresh() -> void:
	for slot in Settings.SLOT_COUNT:
		for lane in Lanes.COUNT:
			var btn: Button = _key_buttons[slot][lane]
			var assigned := Settings.binding(slot, lane) != Settings.NO_KEY
			if _waiting_slot == slot and _waiting_lane == lane:
				btn.text = "pulsa..."
			elif assigned:
				btn.text = Lanes.key_label(lane, slot)
			else:
				btn.text = "- sin asignar -"
			btn.modulate = Color(1, 1, 1, 1.0 if assigned else 0.5)

	for lane in Lanes.COUNT:
		var empty := Settings.binding(Settings.SLOT_SECONDARY, lane) == Settings.NO_KEY
		_clear_buttons[lane].disabled = empty

	_offset_label.text = "%+d ms" % Settings.offset_ms

	for slot in Settings.SLOT_COUNT:
		var preset := Settings.current_preset(slot)
		if preset != "":
			_preset_labels[slot].text = preset
		elif Settings.slot_is_empty(slot):
			_preset_labels[slot].text = "ninguna"
		else:
			_preset_labels[slot].text = "a medida"


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _on_rebind(slot: int, lane: int) -> void:
	_waiting_slot = slot
	_waiting_lane = lane
	_set_status("Esperando tecla para %s (%s)..." % [
		Lanes.NAMES[lane], Settings.SLOT_NAMES[slot].to_lower()], Color("ffd23f"))
	_refresh()


func _on_clear(lane: int) -> void:
	_cancel_wait()
	var err := Settings.clear_binding(Settings.SLOT_SECONDARY, lane)
	if err == "":
		_set_status("%s se queda sin tecla secundaria" % Lanes.NAMES[lane], Color("888899"))
	else:
		_set_status(err, Color("f9393f"))
	_refresh()


func _on_preset(slot: int, preset_name: String) -> void:
	_cancel_wait()
	var err := Settings.apply_preset(slot, preset_name)
	if err == "":
		var shown := preset_name if preset_name != "" else "sin teclas"
		_set_status("%s: %s" % [Settings.SLOT_NAMES[slot], shown], Color("2ee6a8"))
	else:
		_set_status(err, Color("f9393f"))
	_refresh()


func _cancel_wait() -> void:
	_waiting_slot = -1
	_waiting_lane = -1


func _go_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## Se usa _input y no _unhandled_input: mientras esperamos una tecla hay que
## capturarla antes de que nadie mas la interprete.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key := event as InputEventKey
	if key.echo:
		return

	if _waiting_slot == -1:
		if key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_go_back()
		return

	get_viewport().set_input_as_handled()
	var slot := _waiting_slot
	var lane := _waiting_lane
	_cancel_wait()

	if key.keycode == KEY_ESCAPE:
		_set_status("Cancelado", Color("888899"))
		_refresh()
		return

	var physical := key.physical_keycode
	if physical == 0:
		physical = key.keycode

	var err := Settings.set_binding(slot, lane, physical)
	if err == "":
		_set_status("%s (%s) = %s" % [Lanes.NAMES[lane],
			Settings.SLOT_NAMES[slot].to_lower(), Lanes.key_name(physical)], Color("2ee6a8"))
	else:
		_set_status(err, Color("f9393f"))
	_refresh()
