extends Control

const EDIT_SCENE := "res://scenes/edit_menu.tscn"
const SELECT_SCENE := "res://scenes/song_select.tscn"
const SETTINGS_SCENE := "res://scenes/settings_scene.tscn"
## Nombre provisional: el modo se llamara de otra forma.
const ROGUE_SCENE := "res://scenes/rogue_menu.tscn"

var _first: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = GuiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := Label.new()
	title.text = "RHYTHM CREATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
	title.add_theme_constant_override("outline_size", 8)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Graba tu propio chart y juegalo"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", GuiTheme.TEXT_DIM)
	root.add_child(sub)

	root.add_child(_spacer(8))

	# Los botones van dentro de la pantalla de casete, como las teclas de un walkman.
	var center := CenterContainer.new()
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	panel.add_child(buttons)

	_first = _menu_button("MODO EDICION",
		func() -> void: get_tree().change_scene_to_file(EDIT_SCENE))
	buttons.add_child(_first)
	buttons.add_child(_menu_button("MODO JUEGO",
		func() -> void: get_tree().change_scene_to_file(SELECT_SCENE)))
	buttons.add_child(_menu_button("ROGUELIKE",
		func() -> void: get_tree().change_scene_to_file(ROGUE_SCENE)))
	buttons.add_child(_menu_button("AJUSTES",
		func() -> void: get_tree().change_scene_to_file(SETTINGS_SCENE)))
	buttons.add_child(_menu_button("SALIR",
		func() -> void: get_tree().quit()))

	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_color", GuiTheme.TEXT_DIM)
	info.add_theme_font_size_override("font_size", 14)
	info.text = "%d grabaciones   -   teclas %s   -   W/S o flechas para moverte, Intro para elegir" % [
		Library.list_songs().size(), Lanes.keys_hint()]
	root.add_child(_spacer(8))
	root.add_child(info)

	# Algo tiene que tener el foco al entrar, o el teclado no navega nada.
	_first.grab_focus.call_deferred()


static func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _menu_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BigButton"
	b.custom_minimum_size = Vector2(320, 58)
	b.pressed.connect(on_press)
	return b
