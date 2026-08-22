extends Control

## Pantalla de Ajustes: reasignar las teclas de los cuatro carriles.
## Cada carril tiene dos: principal y secundaria (esta puede quedar vacia).

const MENU_SCENE := "res://scenes/main_menu.tscn"
const KEY_BTN_SIZE := Vector2(150, 42)

## _key_buttons[slot][lane]
var _key_buttons: Array[Array] = []
var _clear_buttons: Array[Button] = []
var _preset_labels: Array[Label] = []
var _status: Label

## Hueco que espera una tecla, o -1 si no estamos reasignando.
var _waiting_slot := -1
var _waiting_lane := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("14101f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	root.add_child(_center_label("AJUSTES", 34))
	root.add_child(_center_label("Teclas del juego", 19))
	root.add_child(_center_label(
		"Pulsa un hueco y despues la tecla que quieras. Esc cancela.", 13))
	root.add_child(_spacer(8))
	root.add_child(_build_grid())
	root.add_child(_spacer(12))

	for slot in Settings.SLOT_COUNT:
		root.add_child(_build_preset_row(slot))

	root.add_child(_spacer(6))
	_status = _center_label("", 15)
	root.add_child(_status)

	var back := Button.new()
	back.text = "Volver"
	back.custom_minimum_size = Vector2(200, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_go_back)
	root.add_child(back)

	_refresh()


func _build_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)

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
		_key_buttons[slot] = []

	for lane in Lanes.COUNT:
		var arrow := Label.new()
		arrow.text = Lanes.ARROWS[lane]
		arrow.custom_minimum_size = Vector2(30, 0)
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.add_theme_font_size_override("font_size", 24)
		arrow.add_theme_color_override("font_color", Lanes.COLORS[lane])
		grid.add_child(arrow)

		var lane_name := Label.new()
		lane_name.text = Lanes.NAMES[lane]
		lane_name.custom_minimum_size = Vector2(120, 0)
		grid.add_child(lane_name)

		for slot in Settings.SLOT_COUNT:
			var btn := Button.new()
			btn.custom_minimum_size = KEY_BTN_SIZE
			btn.focus_mode = Control.FOCUS_NONE  # que las flechas no naveguen el menu
			btn.add_theme_font_size_override("font_size", 17)
			btn.pressed.connect(_on_rebind.bind(slot, lane))
			grid.add_child(btn)
			_key_buttons[slot].append(btn)

		var clear := Button.new()
		clear.text = "X"
		clear.custom_minimum_size = Vector2(40, KEY_BTN_SIZE.y)
		clear.focus_mode = Control.FOCUS_NONE
		clear.tooltip_text = "Quitar la tecla secundaria"
		clear.pressed.connect(_on_clear.bind(lane))
		grid.add_child(clear)
		_clear_buttons.append(clear)

	return grid


func _build_preset_row(slot: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)

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
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_preset.bind(slot, preset_name))
		row.add_child(b)

	# Solo la secundaria puede quedarse sin teclas.
	if slot == Settings.SLOT_SECONDARY:
		var none := Button.new()
		none.text = "Ninguna"
		none.custom_minimum_size = Vector2(96, 34)
		none.focus_mode = Control.FOCUS_NONE
		none.pressed.connect(_on_preset.bind(slot, ""))
		row.add_child(none)

	var current := _center_label("", 13)
	current.custom_minimum_size = Vector2(150, 0)
	current.modulate = Color(1, 1, 1, 0.55)
	row.add_child(current)
	_preset_labels.append(current)

	return row


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
