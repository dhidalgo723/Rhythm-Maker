extends Control

const MENU_SCENE := "res://scenes/edit_menu.tscn"
const SELECT_SCENE := "res://scenes/song_select.tscn"
const PLAY_SCENE := "res://scenes/play_scene.tscn"
const PAD_SIZE := Vector2(110, 110)

var _rec: RecordingManager
var _time_label: Label
var _diag_label: Label
var _count_label: Label
var _status_label: Label
var _progress: ProgressBar
var _pads: Array[Panel] = []
var _action_btn: Button

var _length_ms := 0.0
var _saved := false


func _ready() -> void:
	if not Session.has_audio():
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

	_rec.start(Session.audio_stream, Session.audio_path)
	_status_label.text = "GRABANDO - toca las flechas al ritmo"


func _build_ui() -> void:
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
	_progress.custom_minimum_size = Vector2(0, 18)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_child(_progress)
	root.add_child(margin)

	var pads := HBoxContainer.new()
	pads.alignment = BoxContainer.ALIGNMENT_CENTER
	pads.add_theme_constant_override("separation", 14)
	root.add_child(pads)

	for i in Lanes.COUNT:
		var pad := Panel.new()
		pad.custom_minimum_size = PAD_SIZE
		_style_pad(pad, i, false)
		var arrow := Label.new()
		arrow.text = Lanes.ARROWS[i]
		arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.add_theme_font_size_override("font_size", 44)
		pad.add_child(arrow)

		# La tecla de cada carril es configurable, asi que se muestra en el pad.
		var key := Label.new()
		key.text = Lanes.key_label_pair(i)
		key.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		key.offset_top = -26
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.add_theme_font_size_override("font_size", 14)
		key.modulate = Color(1, 1, 1, 0.65)
		pad.add_child(key)

		pads.add_child(pad)
		_pads.append(pad)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.text = "0 notas"
	root.add_child(_count_label)

	_action_btn = Button.new()
	_action_btn.text = "Detener y guardar  (Esc)"
	_action_btn.focus_mode = Control.FOCUS_NONE  # que no se coma las flechas
	_action_btn.pressed.connect(_on_action_pressed)
	root.add_child(_action_btn)


func _style_pad(pad: Panel, lane: int, lit: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Lanes.COLORS[lane] if lit else Lanes.COLORS[lane].darkened(0.75)
	sb.border_color = Lanes.COLORS[lane]
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	pad.add_theme_stylebox_override("panel", sb)


func _process(_delta: float) -> void:
	if _rec == null or not _rec.is_recording():
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
		return

	Session.selected_song = null
	_status_label.add_theme_color_override("font_color", Color("12fa05"))
	_status_label.text = "Guardado \"%s\" con %d notas" % [title, chart.notes.size()]
	_action_btn.text = "Volver"

	var play := Button.new()
	play.text = "JUGARLA AHORA"
	play.custom_minimum_size = Vector2(260, 46)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(_on_play_now.bind(title))
	_action_btn.get_parent().add_child(play)
	_action_btn.get_parent().move_child(play, _action_btn.get_index())


func _on_play_now(title: String) -> void:
	for entry in Library.list_songs():
		if entry.title() == title:
			Session.selected_song = entry
			get_tree().change_scene_to_file(PLAY_SCENE)
			return
	get_tree().change_scene_to_file(SELECT_SCENE)


func _on_action_pressed() -> void:
	if _rec.is_recording():
		_rec.stop()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_action_pressed()
