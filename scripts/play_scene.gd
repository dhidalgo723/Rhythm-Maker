extends Control

const SELECT_SCENE := "res://scenes/song_select.tscn"
const COUNTDOWN_S := 3.0

var _pm: PlaybackManager
var _field: PlayField

var _hud_score: Label
var _hud_combo: Label
var _hud_misses: Label
var _judge_label: Label
var _progress: ProgressBar
var _countdown: Label
var _results: PanelContainer
var _results_text: Label
var _results_title: Label
var _pause_panel: PanelContainer

var _entry: SongEntry
var _stream: AudioStream
var _length_ms := 1.0
var _judge_timer := 0.0
var _countdown_left := COUNTDOWN_S
var _started := false
var _paused := false


func _ready() -> void:
	# El nodo sigue vivo hasta que el cambio de escena se aplica al final del
	# frame, asi que hay que parar _process o accedera a una UI que no existe.
	_entry = Session.selected_song
	if _entry == null:
		set_process(false)
		get_tree().change_scene_to_file(SELECT_SCENE)
		return

	_stream = AudioLoader.load_stream(_entry.audio_path())
	if _stream == null:
		push_error("No se pudo cargar el audio de %s" % _entry.title())
		set_process(false)
		get_tree().change_scene_to_file(SELECT_SCENE)
		return
	_length_ms = maxf(_stream.get_length() * 1000.0, 1.0)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

	# La raiz sigue viva en pausa para poder despausar; lo que se congela es el
	# juego en si, marcado como pausable mas abajo.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_pm = PlaybackManager.new()
	_pm.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_pm)
	_field.process_mode = Node.PROCESS_MODE_PAUSABLE
	_field.bind(_pm)
	_pm.note_hit.connect(_on_note_hit)
	_pm.note_missed.connect(_on_note_missed)
	_pm.score_changed.connect(_on_score_changed)
	_pm.song_ended.connect(_on_song_ended)
	_pm.game_over.connect(_on_game_over)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14101f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_field = PlayField.new()
	_field.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_field)

	# --- HUD superior ---
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 8
	top.offset_left = 16
	top.offset_right = -16
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	top.add_child(row)

	_hud_score = _mk_label("0", 26)
	row.add_child(_hud_score)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var title := _mk_label(_entry.title(), 18)
	title.modulate = Color(1, 1, 1, 0.6)
	row.add_child(title)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer2)

	_hud_misses = _mk_label("Fallos 0/%d" % Judgement.MAX_MISSES, 22)
	row.add_child(_hud_misses)

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.max_value = _length_ms
	_progress.custom_minimum_size = Vector2(0, 8)
	top.add_child(_progress)

	# --- Centro: combo, juicio, cuenta atras ---
	_hud_combo = _mk_label("", 44)
	_hud_combo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hud_combo.offset_top = 150
	_hud_combo.offset_left = -200
	_hud_combo.offset_right = 200
	_hud_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hud_combo)

	_judge_label = _mk_label("", 40)
	_judge_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_judge_label.offset_top = 230
	_judge_label.offset_left = -250
	_judge_label.offset_right = 250
	_judge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_judge_label)

	_countdown = _mk_label("", 96)
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.offset_left = -250
	_countdown.offset_right = 250
	_countdown.offset_top = -80
	_countdown.offset_bottom = 80
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_countdown)

	var hint := _mk_label("%s   -   Esc para pausar" % Lanes.keys_hint(), 14)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -30
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.35)
	add_child(hint)

	_build_results()
	_build_pause_panel()


func _build_results() -> void:
	_results = PanelContainer.new()
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.offset_left = -260
	_results.offset_right = 260
	_results.offset_top = -200
	_results.offset_bottom = 200
	_results.visible = false
	add_child(_results)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1e1830")
	sb.border_color = Color("6c5ce7")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(24)
	_results.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_results.add_child(box)

	_results_title = _mk_label("", 40)
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_results_title)

	_results_text = _mk_label("", 20)
	_results_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_results_text)

	var retry := Button.new()
	retry.text = "Reintentar"
	retry.focus_mode = Control.FOCUS_NONE
	retry.pressed.connect(_retry)
	box.add_child(retry)

	var back := Button.new()
	back.text = "Elegir otra cancion"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_leave)
	box.add_child(back)


func _build_pause_panel() -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.offset_left = -180
	_pause_panel.offset_right = 180
	_pause_panel.offset_top = -140
	_pause_panel.offset_bottom = 140
	_pause_panel.visible = false
	add_child(_pause_panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1e1830")
	sb.border_color = Color("ffd23f")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	_pause_panel.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_pause_panel.add_child(box)

	var title := _mk_label("PAUSA", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("ffd23f"))
	box.add_child(title)

	for entry in [
		["Reanudar", func() -> void: _set_paused(false)],
		["Reintentar", _retry],
		["Salir a la lista", _leave],
	]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(0, 42)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(entry[1])
		box.add_child(b)

	var hint := _mk_label("Esc para reanudar", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.5)
	box.add_child(hint)


static func _mk_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	if _paused:
		return

	if not _started:
		_countdown_left -= delta
		if _countdown_left <= 0.0:
			_countdown.text = ""
			_started = true
			_pm.start(_stream, _entry.chart)
		else:
			_countdown.text = str(ceili(_countdown_left))
		return

	if _pm.is_active():
		_progress.value = clampf(_pm.clock.get_time_ms(), 0.0, _length_ms)

	if _judge_timer > 0.0:
		_judge_timer = maxf(0.0, _judge_timer - delta)
		_judge_label.modulate.a = clampf(_judge_timer / 0.25, 0.0, 1.0)


func _on_note_hit(_lane: int, kind: Judgement.Kind, _delta: float) -> void:
	_show_judgement(kind)


func _on_note_missed(_lane: int) -> void:
	_show_judgement(Judgement.Kind.MISS)


func _show_judgement(kind: Judgement.Kind) -> void:
	_judge_label.text = Judgement.NAMES[kind]
	_judge_label.add_theme_color_override("font_color", Judgement.COLORS[kind])
	_judge_label.modulate.a = 1.0
	_judge_timer = 0.45


func _on_score_changed(score: int, combo: int, misses: int) -> void:
	_hud_score.text = str(score)
	_hud_combo.text = "%d" % combo if combo >= 3 else ""
	_hud_misses.text = "Fallos %d/%d" % [misses, Judgement.MAX_MISSES]
	var danger := float(misses) / float(Judgement.MAX_MISSES)
	_hud_misses.add_theme_color_override("font_color",
		Color("ffffff").lerp(Color("f9393f"), clampf(danger, 0.0, 1.0)))


func _on_song_ended() -> void:
	_show_results("CANCION COMPLETADA", Color("2ee6a8"))


func _on_game_over() -> void:
	_show_results("PERDISTE", Color("f9393f"))


func _show_results(title: String, color: Color) -> void:
	_judge_label.text = ""
	_hud_combo.text = ""
	_results_title.text = title
	_results_title.add_theme_color_override("font_color", color)
	_results_text.text = "\n".join([
		"Puntuacion: %d" % _pm.score,
		"Combo maximo: %d" % _pm.max_combo,
		"Perfect: %d    Good: %d    Fallos: %d" % [_pm.perfects, _pm.goods, _pm.misses],
		"Precision: %.1f%%" % _pm.accuracy(),
		"Notas del chart: %d" % _pm.total_notes(),
	])
	_results.visible = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	# Con la partida acabada no hay nada que pausar: Esc sale directamente.
	if _results.visible or not _started:
		_leave()
	else:
		_set_paused(not _paused)


func _set_paused(value: bool) -> void:
	_paused = value
	_pm.clock.set_paused(value)
	get_tree().paused = value
	_pause_panel.visible = value


## Despausar antes de salir: el arbol pausado se queda asi en la escena nueva.
func _leave() -> void:
	if _paused:
		_set_paused(false)
	if _pm != null:
		_pm.stop()
	get_tree().change_scene_to_file(SELECT_SCENE)


func _retry() -> void:
	if _paused:
		_set_paused(false)
	get_tree().reload_current_scene()
