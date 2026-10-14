extends Control

const MENU_SCENE := "res://scenes/edit_menu.tscn"
const SELECT_SCENE := "res://scenes/song_select.tscn"
const PLAY_SCENE := "res://scenes/play_scene.tscn"
const PAD_SIZE := Vector2(110, 110)
## 16 px del sprite x 4: escala entera, el pixel art no se deforma.
const PAD_ICON_PX := 64
## Margen antes de que arranque el audio, para colocar las manos.
const COUNTDOWN_S := 3.0

var _rec: RecordingManager
var _time_label: Label
var _diag_label: Label
var _count_label: Label
var _status_label: Label
var _progress: ProgressBar
## Indexados por id de carril, no por posicion en pantalla.
var _pads: Array[Panel] = []
var _pad_icons: Array[Control] = []
var _action_btn: Button

var _countdown: Label
var _length_ms := 0.0
var _saved := false
var _countdown_left := COUNTDOWN_S
var _started := false


func _ready() -> void:
	if not Session.has_audio():
		set_process(false)
		get_tree().change_scene_to_file(MENU_SCENE)
		return

	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

	_rec = RecordingManager.new()
	add_child(_rec)
	_rec.lane_pressed.connect(_on_lane_pressed)
	_rec.lane_released.connect(_on_lane_released)
	_rec.note_recorded.connect(_on_note_recorded)
	_rec.recording_finished.connect(_on_recording_finished)

	_length_ms = Session.audio_stream.get_length() * 1000.0
	_progress.max_value = _length_ms

	# La grabacion arranca tras la cuenta atras: si empieza de golpe no da
	# tiempo a colocar las manos y las primeras notas salen siempre tarde.
	_status_label.text = "Preparate..."


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

	var song := Label.new()
	song.text = Session.song_name()
	song.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	song.add_theme_font_size_override("font_size", 20)
	root.add_child(song)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color("f9393f"))
	root.add_child(_status_label)

	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 40)
	root.add_child(_time_label)

	_diag_label = Label.new()
	_diag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diag_label.add_theme_color_override("font_color", Color("888888"))
	root.add_child(_diag_label)

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 24)   # alto exacto de la barra del atlas
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_child(_progress)
	root.add_child(margin)

	var pads := HBoxContainer.new()
	pads.alignment = BoxContainer.ALIGNMENT_CENTER
	pads.add_theme_constant_override("separation", 14)
	root.add_child(pads)

	_pads.resize(Lanes.COUNT)
	_pad_icons.resize(Lanes.COUNT)
	for lane in Lanes.DISPLAY_ORDER:
		var pad := Panel.new()
		pad.custom_minimum_size = PAD_SIZE
		_style_pad(pad, lane, false)

		var layout := VBoxContainer.new()
		layout.set_anchors_preset(Control.PRESET_FULL_RECT)
		layout.offset_top = 8
		layout.offset_bottom = -6
		layout.add_theme_constant_override("separation", 2)
		layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(layout)

		var icon_box := CenterContainer.new()
		icon_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(icon_box)
		var icon := KeyIcons.make_icon(lane, PAD_ICON_PX)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if icon is TextureRect:
			icon.modulate = Color.WHITE.lerp(Lanes.COLORS[lane], PlayField.NOTE_TINT)
		icon_box.add_child(icon)

		# La tecla de cada carril es configurable, asi que se muestra en el pad.
		var key := Label.new()
		key.text = Lanes.key_label_pair(lane)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.add_theme_font_size_override("font_size", 13)
		key.modulate = Color(1, 1, 1, 0.7)
		layout.add_child(key)

		pads.add_child(pad)
		_pads[lane] = pad
		_pad_icons[lane] = icon

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.text = "0 notas"
	root.add_child(_count_label)

	_countdown = Label.new()
	_countdown.text = str(ceili(COUNTDOWN_S))
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_size_override("font_size", 56)
	_countdown.add_theme_color_override("font_color", Color("ffd23f"))
	root.add_child(_countdown)

	_action_btn = Button.new()
	_action_btn.text = "Cancelar  (Esc)"
	_action_btn.theme_type_variation = "BigButton"
	_action_btn.custom_minimum_size = Vector2(300, 52)
	_action_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Mientras se graba, WASD, flechas y espacio son carriles: un boton con foco
	# se los comeria. Esc ya cancela/termina sin necesidad de foco.
	_action_btn.focus_mode = Control.FOCUS_NONE
	_action_btn.pressed.connect(_on_action_pressed)
	root.add_child(_action_btn)


func _style_pad(pad: Panel, lane: int, lit: bool) -> void:
	var color := Lanes.COLORS[lane]
	if GuiTheme.available():
		# Visor de LCD sin tenir: multiplicar el morado por el color del carril
		# cambia el tono (el cian sale verde, igual que "arriba"). El color va en
		# la tecla, igual que en las notas del juego.
		var tint := GuiTheme.FOCUS_TINT if lit else Color.WHITE
		pad.add_theme_stylebox_override("panel", GuiTheme.lcd(tint))
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.darkened(0.35) if lit else color.darkened(0.8)
		sb.border_color = color
		sb.set_border_width_all(3)
		pad.add_theme_stylebox_override("panel", sb)

	# La tecla del icono se hunde mientras se mantiene pulsada.
	if lane < _pad_icons.size() and _pad_icons[lane] is TextureRect:
		var variant := KeyIcons.Variant.PRESSED_OUTLINE if lit else KeyIcons.Variant.NORMAL
		(_pad_icons[lane] as TextureRect).texture = KeyIcons.texture(lane, variant, true)


func _process(delta: float) -> void:
	if _rec == null:
		return

	if not _started:
		_countdown_left -= delta
		if _countdown_left <= 0.0:
			_countdown.text = ""
			_started = true
			_rec.start(Session.audio_stream, Session.audio_path)
			_status_label.text = "GRABANDO - toca las flechas al ritmo"
			_action_btn.text = "Detener y guardar  (Esc)"
		else:
			_countdown.text = str(ceili(_countdown_left))
		return

	if not _rec.is_recording():
		return
	var t := _rec.get_time_ms()
	_time_label.text = _format_time(t)
	_progress.value = clampf(t, 0.0, _length_ms)

	# Diagnostico de Fase 1: si "deriva" se queda en pocos ms y estable,
	# la compensacion esta funcionando.
	var raw := _rec.clock.get_raw_audio_time_ms()
	_diag_label.text = "reloj %.1f ms | audio crudo %.1f ms | deriva %+.1f ms | latencia salida %.1f ms" % [
		t, raw, t - raw, AudioServer.get_output_latency() * 1000.0
	]


static func _format_time(ms: float) -> String:
	var total := maxf(ms, 0.0) / 1000.0
	return "%d:%02d.%03d" % [int(total) / 60, int(total) % 60, int(fmod(maxf(ms, 0.0), 1000.0))]


func _on_lane_pressed(lane: int) -> void:
	_style_pad(_pads[lane], lane, true)


func _on_lane_released(lane: int) -> void:
	_style_pad(_pads[lane], lane, false)


func _on_note_recorded(_note: ChartNote) -> void:
	_count_label.text = "%d notas" % _rec.chart.notes.size()


func _on_recording_finished(chart: Chart) -> void:
	if _saved:
		return
	_saved = true
	for i in Lanes.COUNT:
		_style_pad(_pads[i], i, false)

	var title := Session.recording_title if Session.recording_title != "" else Session.song_title()
	var song_dir := Library.save_recording(chart, Session.audio_path, title)
	if song_dir == "":
		_status_label.text = "ERROR al guardar la grabacion (mira la consola)"
		_action_btn.text = "Volver"
		_action_btn.focus_mode = Control.FOCUS_ALL
		_action_btn.grab_focus()
		return

	Session.selected_song = null
	_status_label.add_theme_color_override("font_color", Color("12fa05"))
	_status_label.text = "Guardado \"%s\" con %d notas" % [title, chart.notes.size()]
	_action_btn.text = "Volver"

	var play := Button.new()
	play.text = "JUGARLA AHORA"
	play.theme_type_variation = "BigButton"
	play.custom_minimum_size = Vector2(300, 52)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(_on_play_now.bind(title))
	_action_btn.get_parent().add_child(play)
	_action_btn.get_parent().move_child(play, _action_btn.get_index())

	# Grabacion terminada: ya no hay carriles que proteger, se puede navegar.
	_action_btn.focus_mode = Control.FOCUS_ALL
	play.grab_focus()


func _on_play_now(title: String) -> void:
	for entry in Library.list_songs():
		if entry.title() == title:
			Session.selected_song = entry
			get_tree().change_scene_to_file(PLAY_SCENE)
			return
	get_tree().change_scene_to_file(SELECT_SCENE)


func _on_action_pressed() -> void:
	if not _started:
		get_tree().change_scene_to_file(MENU_SCENE)
	elif _rec.is_recording():
		_rec.stop()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_action_pressed()
