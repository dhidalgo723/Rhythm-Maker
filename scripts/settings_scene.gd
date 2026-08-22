extends Control

## Pantalla de Ajustes: reasignar las teclas de los cuatro carriles.

const MENU_SCENE := "res://scenes/main_menu.tscn"

var _key_buttons: Array[Button] = []
var _status: Label
var _preset_label: Label

## Lane que esta esperando una tecla, o -1 si no estamos reasignando.
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
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	root.add_child(_center_label("AJUSTES", 36))
	root.add_child(_center_label("Teclas del juego", 20))
	root.add_child(_center_label(
		"Pulsa un carril y despues la tecla que quieras. Esc cancela.", 13))
	root.add_child(_spacer(10))

	for lane in Lanes.COUNT:
		root.add_child(_build_row(lane))

	root.add_child(_spacer(14))
	_preset_label = _center_label("", 13)
	root.add_child(_preset_label)

	var presets := HBoxContainer.new()
	presets.alignment = BoxContainer.ALIGNMENT_CENTER
	presets.add_theme_constant_override("separation", 8)
	root.add_child(presets)
	for name in Settings.PRESETS:
		var b := Button.new()
		b.text = name
		b.custom_minimum_size = Vector2(110, 38)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_preset.bind(name))
		presets.add_child(b)

	root.add_child(_spacer(6))
	_status = _center_label("", 15)
	root.add_child(_status)

	var back := Button.new()
	back.text = "Volver"
	back.custom_minimum_size = Vector2(200, 42)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_go_back)
	root.add_child(back)

	_refresh()


func _build_row(lane: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)

	var arrow := Label.new()
	arrow.text = Lanes.ARROWS[lane]
	arrow.custom_minimum_size = Vector2(34, 0)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 26)
	arrow.add_theme_color_override("font_color", Lanes.COLORS[lane])
	row.add_child(arrow)

	var name := Label.new()
	name.text = Lanes.NAMES[lane]
	name.custom_minimum_size = Vector2(130, 0)
	row.add_child(name)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(190, 44)
	btn.focus_mode = Control.FOCUS_NONE   # que las flechas no naveguen el menu
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(_on_rebind.bind(lane))
	row.add_child(btn)
	_key_buttons.append(btn)

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
	for lane in Lanes.COUNT:
		if _waiting_lane == lane:
			_key_buttons[lane].text = "pulsa una tecla..."
		else:
			_key_buttons[lane].text = Lanes.key_label(lane)
	var preset := Settings.current_preset()
	_preset_label.text = "Preset actual: %s" % preset if preset != "" else "Teclas a medida"


func _on_rebind(lane: int) -> void:
	_waiting_lane = lane
	_status.text = "Esperando tecla para %s..." % Lanes.NAMES[lane]
	_status.add_theme_color_override("font_color", Color("ffd23f"))
	_refresh()


func _on_preset(name: String) -> void:
	_waiting_lane = -1
	Settings.apply_preset(name)
	_status.add_theme_color_override("font_color", Color("2ee6a8"))
	_status.text = "Preset %s aplicado" % name
	_refresh()


func _go_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## Se usa _input y no _unhandled_input: mientras esperamos una tecla hay que
## capturarla antes de que nadie mas la interprete.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.echo:
			return

		if _waiting_lane == -1:
			if key.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_go_back()
			return

		get_viewport().set_input_as_handled()
		var lane := _waiting_lane
		_waiting_lane = -1

		if key.keycode == KEY_ESCAPE:
			_status.add_theme_color_override("font_color", Color("888899"))
			_status.text = "Cancelado"
			_refresh()
			return

		var physical := key.physical_keycode
		if physical == 0:
			physical = key.keycode

		if Settings.set_binding(lane, physical):
			_status.add_theme_color_override("font_color", Color("2ee6a8"))
			_status.text = "%s = %s" % [Lanes.NAMES[lane], Lanes.key_name(physical)]
		else:
			_status.add_theme_color_override("font_color", Color("f9393f"))
			_status.text = "Esa tecla esta reservada, elige otra"
		_refresh()
