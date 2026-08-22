extends Control

const EDIT_SCENE := "res://scenes/edit_menu.tscn"
const SELECT_SCENE := "res://scenes/song_select.tscn"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("14101f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	var title := Label.new()
	title.text = "RHYTHM CREATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Graba tu propio chart y juegalo"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.55)
	root.add_child(sub)

	root.add_child(_spacer(30))
	root.add_child(_menu_button("MODO EDICION", Color("00c2ff"),
		func() -> void: get_tree().change_scene_to_file(EDIT_SCENE)))
	root.add_child(_menu_button("MODO JUEGO", Color("12fa05"),
		func() -> void: get_tree().change_scene_to_file(SELECT_SCENE)))
	root.add_child(_spacer(10))
	root.add_child(_menu_button("SALIR", Color("888899"),
		func() -> void: get_tree().quit()))

	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.modulate = Color(1, 1, 1, 0.35)
	info.text = "%d grabaciones guardadas   -   latencia de salida %.0f ms" % [
		Library.list_songs().size(), AudioServer.get_output_latency() * 1000.0]
	root.add_child(_spacer(20))
	root.add_child(info)


static func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _menu_button(text: String, color: Color, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 62)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", color)
	b.pressed.connect(on_press)
	return b
