extends Control

const MENU_SCENE := "res://scenes/main_menu.tscn"
const PLAY_SCENE := "res://scenes/play_scene.tscn"
const EDIT_SCENE := "res://scenes/edit_menu.tscn"

var _list: VBoxContainer
var _empty: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("14101f")
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
	title.text = "ELIGE UNA GRABACION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	root.add_child(title)

	_empty = Label.new()
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.modulate = Color(1, 1, 1, 0.6)
	_empty.text = "No hay grabaciones todavia.\nVe a MODO EDICION para crear una."
	root.add_child(_empty)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var speed_row := HBoxContainer.new()
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_row.add_theme_constant_override("separation", 10)
	root.add_child(speed_row)
	var speed_lbl := Label.new()
	speed_lbl.text = "Velocidad de caida: %d ms" % Settings.travel_time_ms
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
		speed_lbl.text = "Velocidad de caida: %d ms" % Settings.travel_time_ms)
	speed_row.add_child(speed)

	var back := Button.new()
	back.text = "Volver al menu"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	root.add_child(back)

	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()

	var songs := Library.list_songs()
	_empty.visible = songs.is_empty()

	for entry in songs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)

		var play := Button.new()
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.custom_minimum_size = Vector2(0, 54)
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var secs := entry.last_note_ms() / 1000
		play.text = "  %s          %d notas   -   %d:%02d" % [
			entry.title(), entry.note_count(), secs / 60, secs % 60]
		play.pressed.connect(_on_play.bind(entry))
		row.add_child(play)

		var del := Button.new()
		del.text = "X"
		del.custom_minimum_size = Vector2(54, 54)
		del.tooltip_text = "Borrar esta grabacion"
		del.pressed.connect(_on_delete.bind(entry))
		row.add_child(del)


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
