extends Control

## Portada del modo roguelike y mapa de la partida en curso, con aspecto de
## equipo de musica: titulo en una pantalla, placas atornilladas y una pantalla
## cian en el centro.
##   - Sin partida: reglas y "Nueva partida".
##   - Con partida, en tres columnas:
##       izquierda: lo que llevas (monedas, ranura, flechas, mochila)
##       centro: el proximo jefe, las 10 canciones, como fue la ultima y la partida
##       derecha: la siguiente cancion y las habilidades de su jefe

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

# Iconos del atlas GUI/gui retro.png.
const COIN := Rect2i(264, 95, 17, 18)
const HEART := Rect2i(747, 9, 14, 12)
const CROWN := Rect2i(783, 865, 20, 15)
const BACKPACK := Rect2i(781, 795, 50, 62)
const SIGNPOST := Rect2i(330, 133, 32, 52)
const ARROW_YELLOW := Rect2i(700, 170, 42, 23)
const RING := Rect2i(186, 615, 44, 45)
const GEM_GOLD := Rect2i(235, 196, 24, 23)
const GEM_BLUE := Rect2i(260, 195, 25, 25)
const GEM_RED := Rect2i(313, 196, 24, 23)

## Color de la pantalla y de los datos destacados.
const CYAN := Color("4de8ff")
const GREEN := Color("2ee6a8")
const RED := Color("f9393f")
const SIDE_WIDTH := 250

var _pool: RoguePool
var _first: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_pool = RoguePool.load_pool()

	var bg := ColorRect.new()
	bg.color = Color("0e0a14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	add_child(_Stripes.new())

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20
	root.offset_right = -20
	root.offset_top = 10
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.add_child(_title())

	var run: RogueRun = Session.rogue_run
	if run != null and not run.is_over():
		_build_map(root, run)
	else:
		_build_intro(root, run)

	if _first != null:
		_first.grab_focus.call_deferred()


## El titulo, en la pantalla de un aparato.
func _title() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lcd := PanelContainer.new()
	if GuiTheme.available():
		lcd.add_theme_stylebox_override("panel", GuiTheme.lcd(Color.WHITE, [40, 8, 40, 10]))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	lcd.add_child(inner)
	inner.add_child(_icon(GEM_BLUE, 24))
	inner.add_child(_label("ROGUELIKE", 36, CYAN))
	inner.add_child(_icon(GEM_BLUE, 24))
	row.add_child(lcd)
	return row


# ---------------------------------------------------------------- Portada

func _build_intro(root: VBoxContainer, finished: RogueRun) -> void:
	if finished != null and finished.state == RogueRun.State.WON:
		root.add_child(_label(Lang.t("¡Superaste los 10 jefes! Partida ganada."), 20, GREEN, 3, true))
	elif finished != null and finished.state == RogueRun.State.LOST:
		root.add_child(_label(Lang.t("Perdiste en la canción %d de %d.") % [
			finished.index + 1, finished.songs_total()], 20, RED, 3, true))

	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var rules := _label("\n".join(RogueCatalog.rules_lines()), 15, GuiTheme.TEXT, 3)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(rules)

	var missing := _pool.missing_sizes()
	if not _pool.problems.is_empty() or not missing.is_empty():
		var msg: Array[String] = []
		for p in _pool.problems:
			msg.append(p)
		if not missing.is_empty():
			msg.append(Lang.t("Faltan canciones de tamaño: %s (en roguelike/pool.json)") % ", ".join(missing))
		root.add_child(_label("\n".join(msg), 13, Color("ff9f43"), 3, true))

	var buttons := _button_row(root)
	var start := _big(Lang.t("Nueva partida"), _on_new_run)
	start.disabled = not missing.is_empty()
	buttons.add_child(start)
	buttons.add_child(_big(Lang.t("Volver al menú"), _go_menu))
	_first = start if not start.disabled else buttons.get_child(1)


func _on_new_run() -> void:
	Session.rogue_run = RogueRun.create(_pool)
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- Mapa

func _build_map(root: VBoxContainer, run: RogueRun) -> void:
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	cols.add_child(_side_panel(_equipment(run)))
	var center := _center(run)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(center)
	cols.add_child(_side_panel(_next_song(run)))

	var buttons := _button_row(root)
	if run.state == RogueRun.State.SHOP:
		_first = _big(Lang.t("Ir a la venta de garaje"),
			func() -> void: get_tree().change_scene_to_file(SHOP_SCENE))
	else:
		_first = _big(Lang.t("Tocar canción %d") % (run.index + 1), _on_play)
	buttons.add_child(_first)
	buttons.add_child(_big(Lang.t("Abandonar partida"), _on_abandon))
	buttons.add_child(_big(Lang.t("Menú principal"), _go_menu))


func _side_panel(content: Control) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	panel.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	panel.add_child(content)
	return panel


## Izquierda: monedas, ranura, flechas y mochila.
func _equipment(run: RogueRun) -> Control:
	var box := _vbox(10)
	box.add_child(_heading(Lang.t("TU EQUIPO")))
	box.add_child(_icon_row(COIN, 30, Lang.t("MONEDAS"), Lang.number(run.money), GuiTheme.TEXT_FOCUS))

	# Ranura: la imagen de la mejora dentro de un aro (vacio si no hay).
	box.add_child(_small(Lang.t("RANURA")))
	var slot_tex: Texture2D = null
	if run.slot_id != "":
		slot_tex = RogueArt.item_texture(RogueCatalog.ItemKind.SLOT, run.slot_id, 58)
	box.add_child(_ring(slot_tex, 84))
	var slot_name := RogueCatalog.item_name(RogueCatalog.ItemKind.SLOT, run.slot_id) \
		if run.slot_id != "" else Lang.t("vacía")
	box.add_child(_label(slot_name, 13, GuiTheme.TEXT if run.slot_id != "" else GuiTheme.TEXT_DIM, 3, true))

	# Flechas: las 5 teclas; las mejoradas, de su color y con una gema debajo.
	box.add_child(_small(Lang.t("FLECHAS")))
	var keys := HBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.add_theme_constant_override("separation", 4)
	var upgraded: Array[String] = []
	for lane in Lanes.DISPLAY_ORDER:
		var col := _vbox(2)
		var key := KeyIcons.make_icon(lane, 38)
		var id := run.arrow_on(lane)
		var gem: Control = Control.new()
		if id != "":
			key.modulate = Color(str(RogueCatalog.ARROW[id]["color"]))
			gem = _icon(GEM_GOLD, 14)
			var left := int(run.arrows[lane]["songs_left"])
			var extra := " (%d)" % left if left > 0 else ""
			upgraded.append("%s: %s%s" % [Lanes.lane_name(lane),
				RogueCatalog.item_name(RogueCatalog.ItemKind.ARROW, id), extra])
		gem.custom_minimum_size = Vector2(38, 14)
		col.add_child(key)
		col.add_child(gem)
		keys.add_child(col)
	box.add_child(keys)
	if upgraded.is_empty():
		box.add_child(_label(Lang.t("ninguna mejorada"), 11, GuiTheme.TEXT_DIM, 2, true))
	else:
		box.add_child(_label("\n".join(upgraded), 11, GuiTheme.TEXT_FOCUS, 2, true))

	# Mochila: los consumibles comprados para la siguiente cancion.
	var bag: Array[String] = []
	for id in run.pending:
		bag.append(RogueCatalog.item_name(RogueCatalog.ItemKind.CONSUMABLE, id))
	box.add_child(_icon_row(BACKPACK, 30, Lang.t("MOCHILA"),
		", ".join(bag) if not bag.is_empty() else Lang.t("vacía"),
		GuiTheme.TEXT if not bag.is_empty() else GuiTheme.TEXT_DIM))
	return box


## Derecha: la siguiente cancion y las habilidades de su jefe.
func _next_song(run: RogueRun) -> Control:
	var boss := run.current_boss()
	var spec := boss.spec()
	var song := _pool.find(boss.song_id)
	var box := _vbox(10)
	box.add_child(_heading(Lang.t("SIGUIENTE")))
	box.add_child(_icon_row(CROWN, 24, Lang.t("JEFE"), boss.title(), GuiTheme.TEXT_FOCUS))
	box.add_child(_icon_row(SIGNPOST, 30, Lang.t("CANCIÓN"), str(song.get("title", boss.song_id)),
		GuiTheme.TEXT))
	box.add_child(_icon_row(ARROW_YELLOW, 18, Lang.t("RITMO"), "%s · %s" % [
		RogueCatalog.duration_text(int(spec["duration_ms"])), RogueCatalog.speed_name(spec["speed"])],
		GuiTheme.TEXT))
	box.add_child(_icon_row(HEART, 22, Lang.t("FALLOS"), Lang.t("%d permitidos") % boss.miss_limit(),
		GuiTheme.TEXT))

	box.add_child(_small(Lang.t("HABILIDAD") if boss.abilities.size() == 1 else Lang.t("HABILIDADES")))
	if not boss.revealed:
		box.add_child(_ability_row("???"))
		box.add_child(_label(Lang.t("Se revelan al empezar la canción (o con un Setlist)."),
			11, GuiTheme.TEXT_DIM, 2, true))
	elif boss.abilities.size() == 1:
		box.add_child(_ability_row(RogueCatalog.ability_name(boss.abilities[0])))
		box.add_child(_label(RogueCatalog.ability_desc(boss.abilities[0]), 11, GuiTheme.TEXT, 2, true))
	else:
		# El jefe final trae varias: solo los nombres (el detalle esta en
		# Ajustes > Informacion).
		for id in boss.abilities:
			box.add_child(_ability_row(RogueCatalog.ability_name(id)))
	return box


func _ability_row(ability_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_icon(GEM_RED, 20))
	var l := _label(ability_name, 15, RED, 3)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	return row


## Centro: la pantalla cian con el proximo jefe, la ultima cancion y la partida.
func _center(run: RogueRun) -> Control:
	var boss := run.current_boss()
	var spec := boss.spec()
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	var stack := Control.new()
	panel.add_child(stack)
	var box := _vbox(8)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(box)
	var lines := _Scanlines.new()
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(lines)

	box.add_child(_label(Lang.t("PRÓXIMO JEFE"), 13, GuiTheme.TEXT_DIM, 0, true))
	box.add_child(_label(Lang.t("%s  ·  CANCIÓN %d DE %d") % [
		boss.title().to_upper(), run.index + 1, run.songs_total()], 22, CYAN, 4, true))
	box.add_child(_boss_strip(run))
	var goal := Lang.t("Objetivo: %s puntos") % Lang.number(
		RogueCatalog.score_target(run.index, int(spec["notes"])))
	var reward: int = RogueCatalog.REWARD_BASE[boss.size] + RogueCatalog.REWARD_BONUS[boss.size]
	if reward > 0:
		goal += "  ·  " + Lang.t("Si la pasas: hasta %d monedas") % reward
	box.add_child(_label(goal, 13, GuiTheme.TEXT, 3, true))

	box.add_child(_rule())
	var last := run.last_result
	if last.has("boss_index"):
		var last_boss: RogueBoss = run.bosses[int(last["boss_index"])]
		box.add_child(_label(Lang.t("ÚLTIMA CANCIÓN  ·  %s") % last_boss.title().to_upper(),
			14, GuiTheme.TEXT_DIM, 0, true))
		var limit := maxi(1, int(last["miss_limit"]))
		box.add_child(_stat(Lang.t("PRECISIÓN"), "%s %%" % Lang.decimal(float(last["accuracy"])),
			float(last["accuracy"]), GREEN))
		box.add_child(_stat(Lang.t("FALLOS"), "%d / %d" % [int(last["misses"]), limit],
			100.0 * int(last["misses"]) / limit, RED))
		var target := maxi(1, int(last["target"]))
		box.add_child(_stat(Lang.t("PUNTUACIÓN"), "%s / %s" % [Lang.number(int(last["score"])),
			Lang.number(target)], 100.0 * int(last["score"]) / target, CYAN))
		box.add_child(_stat_text(Lang.t("PERFECTOS · COMBO"), "%d · %d" % [
			int(last["perfects"]), int(last["max_combo"])]))
		box.add_child(_stat_text(Lang.t("DINERO GANADO"), Lang.t("+%d monedas") % int(last["money"])))
	else:
		box.add_child(_label(Lang.t("ÚLTIMA CANCIÓN"), 14, GuiTheme.TEXT_DIM, 0, true))
		box.add_child(_label(Lang.t("Todavía no has tocado ninguna canción de esta partida."),
			14, GuiTheme.TEXT, 3, true))

	box.add_child(_rule())
	box.add_child(_label(Lang.t("PARTIDA"), 14, GuiTheme.TEXT_DIM, 0, true))
	box.add_child(_stat_text(Lang.t("JEFES SUPERADOS"), Lang.t("%d de %d") % [
		run.bosses_beaten, run.songs_total()]))
	if boss.size == RogueCatalog.Size.FINAL:
		box.add_child(_stat_text(Lang.t("VUELTA"), Lang.t("Final")))
	else:
		var round_i := run.index / 3
		box.add_child(_stat_text(Lang.t("VUELTA"), Lang.t("%d de %d  (fallos x%s)") % [round_i + 1,
			RogueCatalog.ROUND_MISS_FACTOR.size(), Lang.decimal(RogueCatalog.ROUND_MISS_FACTOR[round_i], 2)]))
	return panel


## Las 10 canciones: las pasadas con OK, la actual iluminada.
func _boss_strip(run: RogueRun) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for boss in run.bosses:
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(44, 40)
		if GuiTheme.available():
			var tint := GuiTheme.FOCUS_TINT if boss.index == run.index else Color.WHITE
			chip.add_theme_stylebox_override("panel", GuiTheme.lcd(tint, [2, 2, 2, 2]))
		var color := GuiTheme.TEXT_DIM
		var text := _size_letter(boss.size)
		if boss.index < run.index:
			color = GREEN
			text = "OK"
		elif boss.index == run.index:
			color = CYAN
		chip.add_child(_label("%d\n%s" % [boss.index + 1, text], 11, color, 0, true))
		row.add_child(chip)
	return row


## Fila de dato con barra de vumetro.
func _stat(title: String, value: String, percent: float, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_l := _label(title, 14, GuiTheme.TEXT, 3)
	name_l.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.value = clampf(percent, 0.0, 100.0)
	bar.custom_minimum_size = Vector2(0, 20)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(color, 0.15)
	back.border_color = Color(color, 0.5)
	back.set_border_width_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	row.add_child(bar)
	var v := _label(value, 14, color, 3)
	v.custom_minimum_size = Vector2(140, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row


func _stat_text(title: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var name_l := _label(title, 14, GuiTheme.TEXT, 3)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	row.add_child(_label(value, 14, CYAN, 3))
	return row


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(CYAN, 0.35)
	r.custom_minimum_size = Vector2(0, 2)
	return r


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

func _heading(text: String) -> Label:
	return _label(text, 17, CYAN, 4, true)


func _small(text: String) -> Label:
	return _label(text, 11, GuiTheme.TEXT_DIM, 2)


## Icono dentro de un aro, con un titulo pequeno y el dato debajo.
func _icon_row(region: Rect2i, px: int, title: String, value: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var ring := _ring(null, 44)
	var ic := _icon(region, px)
	ic.position = (Vector2(44, 44) - ic.custom_minimum_size) / 2
	ring.add_child(ic)
	row.add_child(ring)
	var col := _vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_small(title))
	var value_l := _label(value, 14, color, 3)
	value_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(value_l)
	row.add_child(col)
	return row


## Aro del atlas con una imagen dentro (o vacio).
func _ring(content: Texture2D, px: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px, px)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ring := TextureRect.new()
	ring.texture = GuiTheme.piece(RING, 1)
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(ring)
	if content != null:
		var inner := TextureRect.new()
		inner.texture = content
		inner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		inner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		var pad := px * 0.18
		inner.offset_left = pad
		inner.offset_top = pad
		inner.offset_right = -pad
		inner.offset_bottom = -pad
		holder.add_child(inner)
	return holder


## Pieza del atlas a la escala entera mas cercana a `px` de alto.
func _icon(region: Rect2i, px: int) -> TextureRect:
	var scale := maxi(1, roundi(float(px) / region.size.y))
	var t := TextureRect.new()
	t.texture = GuiTheme.piece(region, scale)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.custom_minimum_size = Vector2(region.size) * scale
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## Etiqueta. Las centradas ajustan linea (van en columnas que les dan el
## ancho); dentro de una fila horizontal una etiqueta con ajuste se queda sin
## ancho y escribe una letra por linea.
static func _label(text: String, font_size: int, color: Color, outline: int = 3,
		center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _vbox(separation: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


static func _button_row(root: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	root.add_child(row)
	return row


static func _big(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BigButton"
	b.custom_minimum_size = Vector2(250, 54)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(on_press)
	return b


## Letra del tamano en las fichas del mapa. Va aparte de Lang: una letra suelta
## como clave de traduccion acabaria traduciendo tambien una tecla "G" o "J".
static func _size_letter(size: RogueCatalog.Size) -> String:
	if TranslationServer.get_locale().begins_with("es"):
		return SIZE_LETTER[size]
	return SIZE_LETTER_EN[size]


## Rayas horizontales suaves, como la carcasa de un equipo de musica.
class _Stripes extends Control:
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for y in range(0, int(size.y), 4):
			draw_rect(Rect2(0, y, size.x, 2), Color(1, 1, 1, 0.025))


## Lineas de barrido de pantalla sobre el centro.
class _Scanlines extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for y in range(0, int(size.y), 3):
			draw_rect(Rect2(0, y, size.x, 1), Color(0, 0, 0, 0.28))
