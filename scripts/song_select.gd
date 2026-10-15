extends Control

const MENU_SCENE := "res://scenes/main_menu.tscn"
const PLAY_SCENE := "res://scenes/play_scene.tscn"
const EDIT_SCENE := "res://scenes/edit_menu.tscn"

var _list: VBoxContainer
var _empty: Label
var _back: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = GuiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = Lang.t("ELIGE UNA GRABACIÓN")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
	root.add_child(title)

	_empty = Label.new()
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.modulate = Color(1, 1, 1, 0.6)
	_empty.text = Lang.t("No hay grabaciones todavía.\nVe a MODO EDICIÓN para crear una.")
	root.add_child(_empty)

	# La lista va dentro de una placa oscura con tornillos.
	var list_box := PanelContainer.new()
	list_box.theme_type_variation = "InsetPanel"
	list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(list_box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Al bajar con el teclado, la lista se desplaza sola hasta la cancion elegida.
	scroll.follow_focus = true
	list_box.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var speed_row := HBoxContainer.new()
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_row.add_theme_constant_override("separation", 10)
	root.add_child(speed_row)
	var speed_lbl := Label.new()
	speed_lbl.text = _lead_text()
	speed_row.add_child(speed_lbl)
	var speed := HSlider.new()
	speed.min_value = 500
	speed.max_value = 2500
	speed.step = 50
	speed.value = Settings.travel_time_ms
	speed.custom_minimum_size = Vector2(240, 0)
	speed.value_changed.connect(func(v: float) -> void:
		Settings.travel_time_ms = int(v)
		Settings.save_settings()
		speed_lbl.text = _lead_text())
	speed_row.add_child(speed)

	_back = Button.new()
	_back.text = Lang.t("Volver al menú")
	_back.custom_minimum_size = Vector2(220, 40)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	root.add_child(_back)

	_refresh()


## "Velocidad 500 ms" se leia al reves (numero bajo = las notas salen tarde),
## asi que se dice directamente cuanto antes aparecen.
static func _lead_text() -> String:
	return Lang.t("Las notas aparecen %.1f s antes (más = las ves antes)") % (Settings.travel_time_ms / 1000.0)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()

	var songs := Library.list_songs()
	_empty.visible = songs.is_empty()

	var first: Button = null
	for entry in songs:
		var row := HBoxContainer.new()
		# Hueco para el cursor de seleccion cuando esta en la X.
		row.add_theme_constant_override("separation", 22)
		_list.add_child(row)

		var play := Button.new()
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.custom_minimum_size = Vector2(0, 54)
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var secs := entry.last_note_ms() / 1000
		play.text = Lang.t("  %s          %d notas   -   %d:%02d") % [
			entry.title(), entry.note_count(), secs / 60, secs % 60]
		play.pressed.connect(_on_play.bind(entry))
		row.add_child(play)
		if first == null:
			first = play

		var del := Button.new()
		del.text = "X"
		del.custom_minimum_size = Vector2(54, 54)
		del.tooltip_text = Lang.t("Borrar esta grabación")
		del.pressed.connect(_on_delete.bind(entry))
		row.add_child(del)

	# Diferido: los botones viejos se liberan al final del frame.
	var target := first if first != null else _back
	target.grab_focus.call_deferred()


func _on_play(entry: SongEntry) -> void:
	Session.selected_song = entry
	get_tree().change_scene_to_file(PLAY_SCENE)


func _on_delete(entry: SongEntry) -> void:
	Library.delete_song(entry)
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(MENU_SCENE)
