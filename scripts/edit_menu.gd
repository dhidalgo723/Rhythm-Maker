extends Control

const MENU_SCENE := "res://scenes/main_menu.tscn"
const RECORDING_SCENE := "res://scenes/recording_scene.tscn"

var _file_label: Label
var _warning: Label
var _load_btn: Button
var _record_btn: Button
var _title_edit: LineEdit
var _dialog: FileDialog


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = GuiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Todo el contenido dentro de la pantalla de casete, centrado en pantalla.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var title := _center_label("MODO EDICION", 36)
	title.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
	root.add_child(title)
	root.add_child(_center_label(
		"1. Carga un audio   2. Grabalo tocando las flechas   3. Se guarda en tu biblioteca", 14))

	_file_label = _center_label("Ningun audio cargado", 20)
	root.add_child(_file_label)

	_warning = _center_label("", 14)
	_warning.add_theme_color_override("font_color", Color("ffb347"))
	root.add_child(_warning)

	_load_btn = Button.new()
	_load_btn.text = "Cargar audio (WAV / MP3 / OGG)"
	_load_btn.theme_type_variation = "BigButton"
	_load_btn.custom_minimum_size = Vector2(460, 52)
	_load_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_load_btn.pressed.connect(_on_load_pressed)
	root.add_child(_load_btn)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 8)
	root.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "Nombre:"
	name_row.add_child(name_lbl)
	_title_edit = LineEdit.new()
	_title_edit.custom_minimum_size = Vector2(260, 0)
	_title_edit.placeholder_text = "titulo de la grabacion"
	name_row.add_child(_title_edit)

	_record_btn = Button.new()
	_record_btn.text = "EMPEZAR GRABACION"
	_record_btn.theme_type_variation = "BigButton"
	_record_btn.custom_minimum_size = Vector2(460, 56)
	_record_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_record_btn.disabled = true
	_record_btn.pressed.connect(_on_record_pressed)
	root.add_child(_record_btn)

	var back := Button.new()
	back.text = "Volver"
	back.custom_minimum_size = Vector2(200, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	root.add_child(back)

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.filters = AudioLoader.FILE_FILTERS
	_dialog.file_selected.connect(_on_file_selected)
	# Al cerrar el dialogo sin elegir, el foco vuelve a donde estaba.
	_dialog.canceled.connect(func() -> void: _load_btn.grab_focus())
	add_child(_dialog)

	_refresh()
	_load_btn.grab_focus.call_deferred()


static func _center_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _on_load_pressed() -> void:
	_dialog.current_dir = Settings.last_audio_dir
	_dialog.popup_centered_ratio(0.7)


func _on_file_selected(path: String) -> void:
	if not Session.set_audio(path):
		_file_label.text = "No se pudo cargar: %s" % path.get_file()
		return
	_title_edit.text = Session.song_title()
	_refresh()
	# Con el audio cargado, lo siguiente natural es grabar.
	_record_btn.grab_focus()


func _refresh() -> void:
	if Session.has_audio():
		var len_s := Session.audio_stream.get_length()
		_file_label.text = "%s  (%d:%02d)" % [
			Session.song_name(), int(len_s) / 60, int(len_s) % 60]
		_record_btn.disabled = false
		_warning.text = "" if AudioLoader.is_timing_reliable(Session.audio_path) \
			else "MP3: el decoder puede meter padding al inicio. Para timing exacto, usa WAV."
	else:
		_file_label.text = "Ningun audio cargado"
		_record_btn.disabled = true
		_warning.text = ""


func _on_record_pressed() -> void:
	Session.recording_title = _title_edit.text.strip_edges()
	if Session.recording_title == "":
		Session.recording_title = Session.song_title()
	get_tree().change_scene_to_file(RECORDING_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(MENU_SCENE)
