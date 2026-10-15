extends Control

## Portada del modo roguelike y mapa de la partida en curso.
##   - Sin partida: reglas y "Nueva partida".
##   - Con partida: las 10 canciones, el dinero, lo que llevas y el siguiente
##     jefe, con un boton para tocarlo.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const PLAY_SCENE := "res://scenes/play_scene.tscn"
const SHOP_SCENE := "res://scenes/rogue_shop.tscn"

const SIZE_LETTER := {
	RogueCatalog.Size.SMALL: "P",
	RogueCatalog.Size.MEDIUM: "M",
	RogueCatalog.Size.BIG: "G",
	RogueCatalog.Size.FINAL: "J",
}
## Las mismas en ingles: Small, Medium, Big, Final.
const SIZE_LETTER_EN := {
	RogueCatalog.Size.SMALL: "S",
	RogueCatalog.Size.MEDIUM: "M",
	RogueCatalog.Size.BIG: "B",
	RogueCatalog.Size.FINAL: "F",
}

var _pool: RoguePool
var _first: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_pool = RoguePool.load_pool()

	var bg := ColorRect.new()
	bg.color = GuiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 50)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := _label("ROGUELIKE", 40, GuiTheme.TEXT_FOCUS)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var run: RogueRun = Session.rogue_run
	if run != null and not run.is_over():
		_build_map(root, run)
	else:
		_build_intro(root, run)

	if _first != null:
		_first.grab_focus.call_deferred()


# ---------------------------------------------------------------- Portada

func _build_intro(root: VBoxContainer, finished: RogueRun) -> void:
	if finished != null and finished.state == RogueRun.State.WON:
		root.add_child(_centered(_label(Lang.t("¡Superaste los 10 jefes! Partida ganada."), 20, Color("2ee6a8"))))
	elif finished != null and finished.state == RogueRun.State.LOST:
		root.add_child(_centered(_label(Lang.t("Perdiste en la canción %d de %d.") % [
			finished.index + 1, finished.songs_total()], 20, Color("f9393f"))))

	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var rules := _label("\n".join(RogueCatalog.rules_lines()), 15, GuiTheme.TEXT)
	panel.add_child(rules)

	var missing := _pool.missing_sizes()
	if not _pool.problems.is_empty() or not missing.is_empty():
		var msg: Array[String] = []
		for p in _pool.problems:
			msg.append(p)
		if not missing.is_empty():
			msg.append(Lang.t("Faltan canciones de tamaño: %s (en roguelike/pool.json)") % ", ".join(missing))
		root.add_child(_centered(_label("\n".join(msg), 13, Color("ff9f43"))))

	var buttons := _button_row(root)
	var start := _plank(Lang.t("Nueva partida"), _on_new_run)
	start.disabled = not missing.is_empty()
	buttons.add_child(start)
	buttons.add_child(_plank(Lang.t("Volver al menú"), _go_menu))
	_first = start if not start.disabled else buttons.get_child(1)


func _on_new_run() -> void:
	Session.rogue_run = RogueRun.create(_pool)
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- Mapa

func _build_map(root: VBoxContainer, run: RogueRun) -> void:
	# Las 10 canciones en fila.
	var track := HBoxContainer.new()
	track.alignment = BoxContainer.ALIGNMENT_CENTER
	track.add_theme_constant_override("separation", 8)
	root.add_child(track)
	for boss in run.bosses:
		track.add_child(_boss_chip(boss, run.index))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	var left := PanelContainer.new()
	left.theme_type_variation = "InsetPanel"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(_inventory_text(run))

	var right := PanelContainer.new()
	right.theme_type_variation = "InsetPanel"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(_next_boss_text(run))

	var buttons := _button_row(root)
	if run.state == RogueRun.State.SHOP:
		_first = _plank(Lang.t("Ir a la venta de garaje"),
			func() -> void: get_tree().change_scene_to_file(SHOP_SCENE))
	else:
		_first = _plank(Lang.t("Tocar canción %d") % (run.index + 1), _on_play)
	buttons.add_child(_first)
	buttons.add_child(_plank(Lang.t("Abandonar partida"), _on_abandon))
	buttons.add_child(_plank(Lang.t("Menú principal"), _go_menu))


func _boss_chip(boss: RogueBoss, current: int) -> Control:
	var chip := PanelContainer.new()
	chip.theme_type_variation = "InsetPanel"
	chip.custom_minimum_size = Vector2(70, 0)
	var l := _label("%d\n%s" % [boss.index + 1, _size_letter(boss.size)], 16, GuiTheme.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if boss.index < current:
		l.add_theme_color_override("font_color", Color("2ee6a8"))
		l.text = "%d\nOK" % (boss.index + 1)
	elif boss.index == current:
		l.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
	else:
		l.add_theme_color_override("font_color", GuiTheme.TEXT_DIM)
	chip.add_child(l)
	return chip


func _inventory_text(run: RogueRun) -> Label:
	var lines: Array[String] = [Lang.t("Dinero: %d monedas") % run.money, ""]
	var slot: String = RogueCatalog.item_name(RogueCatalog.ItemKind.SLOT, run.slot_id) if run.slot_id != "" else Lang.t("vacía")
	lines.append(Lang.t("Ranura: %s") % slot)
	lines.append("")
	lines.append(Lang.t("Flechas:"))
	var any := false
	for lane in Lanes.DISPLAY_ORDER:
		var id := run.arrow_on(lane)
		if id == "":
			continue
		any = true
		var left := int(run.arrows[lane]["songs_left"])
		var extra := Lang.t(" (%d canciones)") % left if left > 0 else ""
		lines.append("  %s: %s%s" % [Lanes.lane_name(lane), RogueCatalog.item_name(RogueCatalog.ItemKind.ARROW, id), extra])
	if not any:
		lines.append(Lang.t("  ninguna mejorada"))
	if not run.pending.is_empty():
		lines.append("")
		lines.append(Lang.t("Para la siguiente canción:"))
		for id in run.pending:
			lines.append("  %s" % RogueCatalog.item_name(RogueCatalog.ItemKind.CONSUMABLE, id))
	return _label("\n".join(lines), 15, GuiTheme.TEXT)


func _next_boss_text(run: RogueRun) -> Label:
	var boss := run.current_boss()
	var spec := boss.spec()
	var song := _pool.find(boss.song_id)
	var lines: Array[String] = [
		Lang.t("Canción %d: %s") % [boss.index + 1, boss.title()],
		str(song.get("title", boss.song_id)),
		"",
		Lang.t("Duración: %s, velocidad %s") % [RogueCatalog.duration_text(int(spec["duration_ms"])),
			RogueCatalog.speed_name(spec["speed"])],
		Lang.t("Fallos permitidos: %d") % boss.miss_limit(),
		"",
		Lang.t("Habilidades:"),
	]
	if boss.revealed:
		for id in boss.abilities:
			lines.append("  %s — %s" % [RogueCatalog.ability_name(id), RogueCatalog.ability_desc(id)])
	else:
		lines.append(Lang.t("  ??? (se revelan al empezar)"))
	return _label("\n".join(lines), 15, GuiTheme.TEXT)


func _on_play() -> void:
	var prepared := Session.rogue_run.prepare_song()
	if prepared == null:
		push_error("No se pudo preparar la cancion del roguelike")
		return
	Session.rogue_prepared = prepared
	Session.selected_song = null
	get_tree().change_scene_to_file(PLAY_SCENE)


func _on_abandon() -> void:
	Session.rogue_run = null
	get_tree().reload_current_scene()


func _go_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_menu()


# ---------------------------------------------------------------- Ayudas

static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _button_row(root: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	root.add_child(row)
	return row


static func _plank(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BigButton"
	b.custom_minimum_size = Vector2(250, 50)
	b.pressed.connect(on_press)
	return b


## Letra del tamano en las fichas del mapa. Va aparte de Lang: una letra suelta
## como clave de traduccion acabaria traduciendo tambien una tecla "G" o "J".
static func _size_letter(size: RogueCatalog.Size) -> String:
	if TranslationServer.get_locale().begins_with("es"):
		return SIZE_LETTER[size]
	return SIZE_LETTER_EN[size]
