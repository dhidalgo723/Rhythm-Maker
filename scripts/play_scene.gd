extends Control

const SELECT_SCENE := "res://scenes/song_select.tscn"
const ROGUE_SCENE := "res://scenes/rogue_menu.tscn"
const SHOP_SCENE := "res://scenes/rogue_shop.tscn"
const COUNTDOWN_S := 3.0
## Ancho de la franja libre a la izquierda de los carriles (en la ventana base
## de 1152 px los carriles empiezan en x=276).
const SIDE_COLUMN_W := 270.0

var _pm: PlaybackManager
var _field: PlayField

var _hud_score: Label
var _hud_combo: Label
var _hud_misses: Label
var _judge_label: Label
var _timing_label: Label
var _progress: ProgressBar
var _countdown: Label
var _results: PanelContainer
var _results_text: RichTextLabel
var _results_title: Label
var _pause_panel: PanelContainer
var _resume_btn: Button
var _retry_btn: Button

var _entry: SongEntry
var _stream: AudioStream
var _chart: Chart
var _rules: PlayRules
var _message_label: Label
var _message_timer := 0.0

# --- Roguelike (null en modo normal) ---
var _prepared: RoguePrepared
var _rogue: RogueRuntime
var _rogue_hud: RogueHud
var _length_ms := 1.0
## Juego Libre con habilidades: avisos de las habilidades (que carril...).
var _free_notices: Array[String] = []
var _judge_timer := 0.0
var _countdown_left := COUNTDOWN_S
var _started := false
var _paused := false


func _ready() -> void:
	# El nodo sigue vivo hasta que el cambio de escena se aplica al final del
	# frame, asi que hay que parar _process o accedera a una UI que no existe.
	# Roguelike: la cancion ya viene preparada (chart del jefe + reglas).
	_prepared = Session.rogue_prepared
	if _prepared != null:
		_entry = _prepared.entry
		_stream = _prepared.stream
		_chart = _prepared.chart
		_rules = _prepared.rules
		_length_ms = maxf(_prepared.length_ms, 1.0)
	else:
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
		_chart = _entry.chart
		_length_ms = maxf(_stream.get_length() * 1000.0, 1.0)
		if not Session.free_abilities.is_empty():
			_apply_free_abilities()

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

	if _prepared != null:
		_rogue = RogueRuntime.new()
		_rogue.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(_rogue)
		_rogue.setup(Session.rogue_run, _prepared, _pm)
		_rogue_hud = RogueHud.new()
		_rogue_hud.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(_rogue_hud)
		# Encima de los carriles pero debajo de la pausa y los resultados.
		move_child(_rogue_hud, _field.get_index() + 1)
		_rogue_hud.setup(_rogue, _prepared, _pm)
		for text in _prepared.notices:
			_rogue_hud.show_notice(text)
	else:
		_pm.message.connect(_show_message)
		if not Session.free_abilities.is_empty():
			_build_free_abilities_column()


## Juego Libre con habilidades: se aplican igual que en el roguelike, sobre una
## copia del chart (la grabacion guardada no cambia). Cada intento las tira de
## nuevo: los tramos y carriles al azar cambian al reintentar.
func _apply_free_abilities() -> void:
	var p := RoguePrepared.new()
	p.chart = _entry.chart.duplicate_chart()
	p.rules = PlayRules.new()
	var last := 0
	for n in p.chart.notes:
		last = maxi(last, n.end_ms())
	var end := float(p.chart.end_ms) if p.chart.end_ms > 0 else last + PlaybackManager.AFTER_LAST_NOTE_MS
	p.length_ms = minf(_length_ms, end)
	var r := RandomNumberGenerator.new()
	r.randomize()
	RogueBuilder.apply_abilities(Session.free_abilities, p, r)
	_chart = p.chart
	_rules = p.rules
	_free_notices = p.notices


## A la derecha de los carriles, las habilidades puestas y sus avisos.
func _build_free_abilities_column() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	col.offset_left = -SIDE_COLUMN_W
	col.offset_right = -8
	col.offset_top = 84
	col.offset_bottom = -40
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	move_child(col, _field.get_index() + 1)
	var lines: Array[String] = []
	for id in Session.free_abilities:
		lines.append("• " + RogueCatalog.ability_name(id))
	var title := _mk_label(Lang.t("HABILIDADES"), 15)
	title.add_theme_color_override("font_color", Color("ff9f43"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(title)
	var list := _mk_label("\n".join(lines), 13)
	list.add_theme_color_override("font_color", Color("ff9f43"))
	list.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(list)
	if not _free_notices.is_empty():
		var notes := _mk_label("\n".join(_free_notices), 12)
		notes.add_theme_color_override("font_color", GuiTheme.TEXT_DIM)
		notes.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(notes)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = GuiTheme.BG
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

	_hud_misses = _mk_label("", 22)
	var limit := _rules.miss_limit if _rules != null else 0
	_hud_misses.text = Lang.t("Fallos %d/%d") % [0, limit] if limit > 0 else Lang.t("Fallos: %d") % 0
	row.add_child(_hud_misses)

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.max_value = _length_ms
	_progress.custom_minimum_size = Vector2(0, 24)   # alto exacto de la barra del atlas
	top.add_child(_progress)

	# --- Centro: combo, juicio, cuenta atras ---
	# Combo y juicio van en la columna libre a la izquierda de los carriles: en
	# el centro taparian las notas del carril espacio justo cuando caen.
	_hud_combo = _side_label(44, 250)
	add_child(_hud_combo)

	_judge_label = _side_label(40, 310)
	add_child(_judge_label)

	# Debajo del juicio: si fue pronto o tarde, para saber hacia donde corregir.
	_timing_label = _side_label(18, 360)
	add_child(_timing_label)

	_message_label = _side_label(18, 400)
	_message_label.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
	add_child(_message_label)

	_countdown = _mk_label("", 96)
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.offset_left = -250
	_countdown.offset_right = 250
	_countdown.offset_top = -80
	_countdown.offset_bottom = 80
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_countdown)

	var hint := _mk_label(Lang.t("%s   -   Esc para pausar") % Lanes.keys_hint(), 14)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -30
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.35)
	add_child(hint)

	_build_results()
	_build_pause_panel()


func _build_results() -> void:
	_results = PanelContainer.new()
	_results.visible = false
	_centered(_results)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_results.add_child(box)

	_results_title = _mk_label("", 38)
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_results_title)

	# RichText para poder colorear cada nivel con su color.
	_results_text = RichTextLabel.new()
	_results_text.bbcode_enabled = true
	_results_text.fit_content = true
	_results_text.scroll_active = false
	_results_text.custom_minimum_size = Vector2(380, 0)
	_results_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_text.add_theme_font_size_override("normal_font_size", 18)
	box.add_child(_results_text)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 22)
	box.add_child(buttons)

	# En el roguelike no se reintenta: un solo boton que lleva a la tienda o al
	# menu del roguelike segun como haya ido.
	if _prepared != null:
		_retry_btn = _plank(Lang.t("Continuar"), _continue_rogue)
		buttons.add_child(_retry_btn)
	else:
		_retry_btn = _plank(Lang.t("Reintentar"), _retry)
		buttons.add_child(_retry_btn)
		buttons.add_child(_plank(Lang.t("Otra canción"), _leave))


func _build_pause_panel() -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.visible = false
	_centered(_pause_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(box)

	var title := _mk_label(Lang.t("PAUSA"), 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
	box.add_child(title)

	_resume_btn = _plank(Lang.t("Reanudar"), func() -> void: _set_paused(false))
	box.add_child(_resume_btn)
	if _prepared != null:
		# Repetir un jefe hasta pasarlo romperia el roguelike.
		box.add_child(_plank(Lang.t("Rendirse"), _give_up))
	else:
		box.add_child(_plank(Lang.t("Reintentar"), _retry))
		box.add_child(_plank(Lang.t("Salir a la lista"), _leave))

	var hint := _mk_label(Lang.t("Esc para reanudar"), 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", GuiTheme.TEXT_DIM)
	box.add_child(hint)


## Mete un panel centrado en pantalla con el tamano que pida su contenido.
func _centered(panel: Control) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.add_child(panel)


func _plank(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BigButton"
	b.custom_minimum_size = Vector2(240, 50)
	b.pressed.connect(on_press)
	return b


## Etiqueta centrada en la franja izquierda, entre el borde y los carriles.
static func _side_label(font_size: int, top: float) -> Label:
	var l := _mk_label("", font_size)
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)
	l.offset_left = 0
	l.offset_right = SIDE_COLUMN_W
	l.offset_top = top
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


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
			_pm.start(_stream, _chart, _rules)
		else:
			_countdown.text = str(ceili(_countdown_left))
		return

	if _pm.is_active():
		_progress.value = clampf(_pm.clock.get_time_ms(), 0.0, _length_ms)

	if _judge_timer > 0.0:
		_judge_timer = maxf(0.0, _judge_timer - delta)
		_judge_label.modulate.a = clampf(_judge_timer / 0.25, 0.0, 1.0)
		_timing_label.modulate.a = _judge_label.modulate.a

	if _message_timer > 0.0:
		_message_timer = maxf(0.0, _message_timer - delta)
		_message_label.modulate.a = clampf(_message_timer / 0.4, 0.0, 1.0)


func _on_note_hit(_lane: int, kind: Judgement.Kind, delta: float) -> void:
	_show_judgement(kind, delta)


func _on_note_missed(_lane: int) -> void:
	_show_judgement(Judgement.Kind.MISS, 0.0)


func _show_judgement(kind: Judgement.Kind, delta: float) -> void:
	_judge_label.text = Judgement.label(kind)
	_judge_label.add_theme_color_override("font_color", Judgement.COLORS[kind])
	_judge_label.modulate.a = 1.0
	var hint := Judgement.timing_hint(kind, delta)
	_timing_label.text = Lang.t(hint) if hint != "" else ""
	_timing_label.add_theme_color_override("font_color", Judgement.COLORS[kind])
	_timing_label.modulate.a = 1.0
	_judge_timer = 0.45


func _on_score_changed(score: int, combo: int, misses: int) -> void:
	_hud_score.text = str(score)
	_hud_combo.text = "%d" % combo if combo >= 3 else ""
	var limit := _pm.rules.miss_limit
	if limit <= 0:
		# Juego Libre: sin limite, solo se cuentan.
		_hud_misses.text = Lang.t("Fallos: %d") % misses
		return
	_hud_misses.text = Lang.t("Fallos %d/%d") % [misses, limit]
	var danger := float(misses) / float(maxi(1, limit))
	_hud_misses.add_theme_color_override("font_color",
		Color("ffffff").lerp(Color("f9393f"), clampf(danger, 0.0, 1.0)))


func _on_song_ended() -> void:
	if _prepared != null:
		_show_rogue_results(false)
	else:
		_show_results(Lang.t("CANCIÓN COMPLETADA"), Color("2ee6a8"))


func _on_game_over() -> void:
	if _prepared != null:
		_show_rogue_results(true)
	else:
		_show_results(Lang.t("PERDISTE"), Color("f9393f"))


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_label.modulate.a = 1.0
	_message_timer = 1.2


## Resultado de una cancion del roguelike: se lo pasa a la partida y dice
## adonde se va despues (tienda, final o vuelta a empezar).
func _show_rogue_results(lost: bool) -> void:
	var run: RogueRun = Session.rogue_run
	var out := run.finish_song(_prepared, {
		"score": _pm.score, "misses": _pm.misses, "lost": lost,
		"coin_perfects": _pm.coin_perfects,
		"accuracy": _pm.accuracy(), "perfects": _pm.count(Judgement.Kind.PERFECT),
		"max_combo": _pm.max_combo,
	})
	_judge_label.text = ""
	_timing_label.text = ""
	_hud_combo.text = ""

	var lines: Array[String] = [
		Lang.t("Puntuación: %d / %d") % [_pm.score, _prepared.target_score],
		Lang.t("Fallos: %d / %d") % [_pm.misses, _pm.rules.miss_limit],
		Lang.t("Precisión: %.1f%%") % _pm.accuracy(),
		"",
	]
	if out["passed"]:
		lines.append(Lang.t("[color=#%s]+%d monedas[/color]  (tienes %d)") % [
			GuiTheme.TEXT_FOCUS.to_html(false), out["money"], run.money])
	else:
		lines.append("[color=#f9393f]%s[/color]" % out["reason"])
		lines.append(Lang.t("La partida vuelve a empezar desde cero."))

	match run.state:
		RogueRun.State.WON:
			_results_title.text = Lang.t("¡HAS GANADO!")
			_results_title.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
			_retry_btn.text = Lang.t("Volver al roguelike")
		RogueRun.State.SHOP:
			_results_title.text = Lang.t("¡JEFE SUPERADO!")
			_results_title.add_theme_color_override("font_color", Color("2ee6a8"))
			_retry_btn.text = Lang.t("Ir a la venta de garaje")
		_:
			_results_title.text = Lang.t("FIN DE LA PARTIDA")
			_results_title.add_theme_color_override("font_color", Color("f9393f"))
			_retry_btn.text = Lang.t("Volver al roguelike")
	_results_text.text = "[center]%s[/center]" % "\n".join(lines)
	_results.visible = true
	_retry_btn.grab_focus()


func _continue_rogue() -> void:
	if _paused:
		_set_paused(false)
	if _pm != null:
		_pm.stop()
	Session.rogue_prepared = null
	var run: RogueRun = Session.rogue_run
	var next := SHOP_SCENE if run != null and run.state == RogueRun.State.SHOP else ROGUE_SCENE
	get_tree().change_scene_to_file(next)


## Rendirse a mitad de cancion: la partida se pierde.
func _give_up() -> void:
	if Session.rogue_run != null:
		Session.rogue_run.state = RogueRun.State.LOST
	_continue_rogue()


func _show_results(title: String, color: Color) -> void:
	_judge_label.text = ""
	_timing_label.text = ""
	_hud_combo.text = ""
	_results_title.text = title
	_results_title.add_theme_color_override("font_color", color)
	var lines: Array[String] = [
		Lang.t("Puntuación: %d") % _pm.score,
		Lang.t("Combo máximo: %d") % _pm.max_combo,
		"",
	]
	for kind in Judgement.ORDER:
		lines.append("[color=#%s]%s[/color]  %d" % [
			Judgement.COLORS[kind].to_html(false), Judgement.label(kind), _pm.count(kind)])
	lines.append("")
	lines.append(Lang.t("Precisión: %.1f%%") % _pm.accuracy())
	lines.append(Lang.t("Notas del chart: %d") % _pm.total_notes())
	_results_text.text = "[center]%s[/center]" % "\n".join(lines)
	_results.visible = true
	# Partida acabada: ya no hay carriles que proteger, se navega con teclado.
	_retry_btn.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	# En el roguelike, Esc durante la cuenta atras no hace nada: los
	# consumibles ya se gastaron al preparar la cancion y salir los perderia.
	if _prepared != null and not _started and not _results.visible:
		return
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
	# En pausa se navega el menu; al volver al juego hay que soltar el foco o el
	# boton se quedaria con WASD, flechas y espacio, que son los carriles.
	if value:
		_resume_btn.grab_focus()
	else:
		get_viewport().gui_release_focus()


## Despausar antes de salir: el arbol pausado se queda asi en la escena nueva.
func _leave() -> void:
	if _prepared != null:
		# Con resultados en pantalla, Esc hace lo mismo que el boton; a mitad de
		# cancion no se llega aqui (Esc pausa).
		_continue_rogue()
		return
	if _paused:
		_set_paused(false)
	if _pm != null:
		_pm.stop()
	get_tree().change_scene_to_file(SELECT_SCENE)


func _retry() -> void:
	if _paused:
		_set_paused(false)
	get_tree().reload_current_scene()
