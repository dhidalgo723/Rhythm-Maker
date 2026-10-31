extends Control

## Pantalla de Ajustes, en cuatro apartados:
##   - Controles: reasignar las teclas de los carriles (principal y secundaria,
##     que puede quedar vacia), presets y latencia.
##   - Idioma: el idioma del juego.
##   - Informacion jefes: reglas del roguelike, puntuacion y habilidades.
##   - Informacion mejoras: mejoras de ranura y de flecha y consumibles.
## Los textos de informacion salen de InfoText.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const CALIBRATION_SCENE := "res://scenes/calibration_scene.tscn"
const KEY_BTN_SIZE := Vector2(150, 36)
## Separacion entre botones de una misma fila: lo que ocupa el cursor de
## seleccion, para que no tape el boton de al lado.
const NAV_GAP := 22
## Cuanto baja el texto de Informacion con Av Pag / Re Pag.
const SCROLL_STEP := 160

enum Tab { CONTROLS, LANGUAGE, BOSSES, UPGRADES }

const TAB_TITLES := {
	Tab.CONTROLS: "CONTROLES",
	Tab.LANGUAGE: "IDIOMA",
	Tab.BOSSES: "INFORMACIÓN JEFES",
	Tab.UPGRADES: "INFORMACIÓN MEJORAS",
}
## Categorias de InfoText de cada apartado de informacion.
const INFO_TABS := {
	Tab.BOSSES: ["rogue_rules", "scoring", "boss_small", "boss_medium", "boss_big", "boss_final"],
	Tab.UPGRADES: ["slot", "arrow", "consumable"],
}

## Se conservan al recargar la escena tras cambiar de idioma.
static var _last_tab := Tab.CONTROLS
## Ultima categoria vista en cada apartado de informacion.
static var _last_category := {Tab.BOSSES: 0, Tab.UPGRADES: 0}

## _key_buttons[slot][lane] y _clear_buttons[lane], indexados por id de carril
## (no por fila: las filas siguen el orden de pantalla, con el espacio en medio).
var _key_buttons: Array[Array] = []
var _clear_buttons: Array[Button] = []
var _preset_labels: Array[Label] = []
var _offset_label: Label
var _status: Label

var _tab_buttons: Array[Button] = []
## Contenido de cada apartado: Tab -> Control.
var _pages := {}
var _language_buttons := {}   # codigo de idioma -> boton
## Por apartado de informacion: {categories, buttons, scroll, text}.
var _info_views := {}

## Hueco que espera una tecla, o -1 si no estamos reasignando.
var _waiting_slot := -1
var _waiting_lane := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = GuiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_top = 14
	root.offset_bottom = -12
	root.offset_left = 24
	root.offset_right = -24
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := _center_label(Lang.t("AJUSTES"), 30)
	title.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
	root.add_child(title)
	root.add_child(_build_tab_row())

	_pages[Tab.CONTROLS] = _build_controls()
	_pages[Tab.LANGUAGE] = _build_language()
	for tab in INFO_TABS:
		_pages[tab] = _build_info(tab)
	for tab in _pages:
		(_pages[tab] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(_pages[tab])

	_status = _center_label("", 15)
	root.add_child(_status)

	var back := Button.new()
	back.text = Lang.t("Volver")
	back.custom_minimum_size = Vector2(200, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_go_back)
	root.add_child(back)

	_refresh()
	for tab in INFO_TABS:
		_show_category(tab, _last_category[tab])
	_show_tab(_last_tab)

	# Algo tiene que tener el foco: lo primero del apartado (en Controles, lo
	# mas probable es venir a cambiar una tecla; tras cambiar de idioma, el
	# idioma elegido).
	_first_of_tab(_last_tab).grab_focus.call_deferred()


# ---------------------------------------------------------------- Pestanas

func _build_tab_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", NAV_GAP)

	for tab in TAB_TITLES:
		var b := Button.new()
		b.text = Lang.t(TAB_TITLES[tab])
		b.custom_minimum_size = Vector2(230, 40)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_on_tab_pressed.bind(tab))
		row.add_child(b)
		_tab_buttons.append(b)
	return row


func _on_tab_pressed(tab: Tab) -> void:
	_cancel_wait()
	_set_status("", GuiTheme.TEXT)
	_refresh()
	_show_tab(tab)
	_first_of_tab(tab).grab_focus()


func _show_tab(tab: Tab) -> void:
	_last_tab = tab
	for t in _pages:
		(_pages[t] as Control).visible = t == tab
	# La pestana abierta, en amarillo; la otra, apagada.
	for i in _tab_buttons.size():
		var active := i == tab
		_tab_buttons[i].modulate = Color.WHITE if active else Color(1, 1, 1, 0.55)
		if active:
			_tab_buttons[i].add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
		else:
			_tab_buttons[i].remove_theme_color_override("font_color")


func _first_of_tab(tab: Tab) -> Button:
	match tab:
		Tab.LANGUAGE:
			return _language_buttons[Settings.language]
		Tab.BOSSES, Tab.UPGRADES:
			return (_info_views[tab]["buttons"] as Array)[_last_category[tab]]
	return _key_buttons[Settings.SLOT_PRIMARY][Lanes.DISPLAY_ORDER[0]]


# ---------------------------------------------------------------- Idioma

func _build_language() -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.add_child(_center_label(Lang.t("Idioma del juego"), 19))
	for code in Lang.CODES:
		var b := Button.new()
		b.text = Lang.NAMES[code]
		b.custom_minimum_size = Vector2(320, 48)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if code == Settings.language:
			b.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
		b.pressed.connect(_on_language_chosen.bind(code))
		box.add_child(b)
		_language_buttons[code] = b
	var hint := _center_label(Lang.t("El cambio se guarda y se aplica al momento."), 13)
	hint.modulate = Color(1, 1, 1, 0.55)
	box.add_child(hint)
	return box


## Cambia el idioma y recarga la pantalla: los textos se ponen al crear cada
## escena, asi que recargar es lo que los traduce todos.
func _on_language_chosen(code: String) -> void:
	if code == Settings.language:
		return
	Settings.set_language(code)
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- Controles

func _build_controls() -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.add_child(_center_label(
		Lang.t("Pulsa un hueco y después la tecla que quieras. Esc cancela."), 13))
	box.add_child(_build_grid())
	box.add_child(_spacer(4))
	for slot in Settings.SLOT_COUNT:
		box.add_child(_build_preset_row(slot))
	box.add_child(_spacer(4))
	box.add_child(_build_latency_row())
	return box


func _build_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", NAV_GAP)
	grid.add_theme_constant_override("v_separation", 4)

	# Cabecera: hueco para la flecha y el nombre, luego un titulo por slot.
	grid.add_child(Control.new())
	grid.add_child(Control.new())
	for slot in Settings.SLOT_COUNT:
		var header := _center_label(Settings.slot_name(slot), 14)
		header.custom_minimum_size = Vector2(KEY_BTN_SIZE.x, 0)
		header.modulate = Color(1, 1, 1, 0.6)
		grid.add_child(header)
	grid.add_child(Control.new())

	_key_buttons.resize(Settings.SLOT_COUNT)
	for slot in Settings.SLOT_COUNT:
		var row_buttons: Array[Button] = []
		row_buttons.resize(Lanes.COUNT)
		_key_buttons[slot] = row_buttons
	_clear_buttons.resize(Lanes.COUNT)

	for lane in Lanes.DISPLAY_ORDER:
		grid.add_child(KeyIcons.make_icon(lane, 32))

		var lane_name := Label.new()
		lane_name.text = Lanes.lane_name(lane)
		lane_name.custom_minimum_size = Vector2(130, 0)
		grid.add_child(lane_name)

		for slot in Settings.SLOT_COUNT:
			var btn := Button.new()
			btn.custom_minimum_size = KEY_BTN_SIZE
			btn.add_theme_font_size_override("font_size", 17)
			btn.pressed.connect(_on_rebind.bind(slot, lane))
			grid.add_child(btn)
			_key_buttons[slot][lane] = btn

		var clear := Button.new()
		clear.text = "X"
		clear.custom_minimum_size = Vector2(40, KEY_BTN_SIZE.y)
		clear.tooltip_text = Lang.t("Quitar la tecla secundaria")
		clear.pressed.connect(_on_clear.bind(lane))
		grid.add_child(clear)
		_clear_buttons[lane] = clear

	return grid


func _build_preset_row(slot: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", NAV_GAP)

	var label := Label.new()
	label.text = "%s:" % Settings.slot_name(slot)
	label.custom_minimum_size = Vector2(130, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	for preset_name in Settings.PRESETS:
		var b := Button.new()
		b.text = Lang.t(preset_name)
		b.custom_minimum_size = Vector2(96, 34)
		b.pressed.connect(_on_preset.bind(slot, preset_name))
		row.add_child(b)

	# Solo la secundaria puede quedarse sin teclas.
	if slot == Settings.SLOT_SECONDARY:
		var none := Button.new()
		none.text = Lang.t("Ninguna")
		none.custom_minimum_size = Vector2(96, 34)
		none.pressed.connect(_on_preset.bind(slot, ""))
		row.add_child(none)

	var current := _center_label("", 13)
	current.custom_minimum_size = Vector2(150, 0)
	current.modulate = Color(1, 1, 1, 0.55)
	row.add_child(current)
	_preset_labels.append(current)

	return row


func _build_latency_row() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_center_label(Lang.t("Latencia"), 19))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", NAV_GAP)
	box.add_child(row)

	var minus := Button.new()
	minus.text = "-5 ms"
	minus.custom_minimum_size = Vector2(80, 34)
	minus.pressed.connect(_nudge_offset.bind(-5))
	row.add_child(minus)

	_offset_label = _center_label("", 17)
	_offset_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(_offset_label)

	var plus := Button.new()
	plus.text = "+5 ms"
	plus.custom_minimum_size = Vector2(80, 34)
	plus.pressed.connect(_nudge_offset.bind(5))
	row.add_child(plus)

	var calibrate := Button.new()
	calibrate.text = Lang.t("Calibrar...")
	calibrate.custom_minimum_size = Vector2(140, 34)
	calibrate.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(CALIBRATION_SCENE))
	row.add_child(calibrate)

	return box


func _nudge_offset(amount: int) -> void:
	_cancel_wait()
	Settings.offset_ms = clampi(Settings.offset_ms + amount, -500, 500)
	Settings.save_settings()
	_set_status("Offset: %+d ms" % Settings.offset_ms, Color("2ee6a8"))
	_refresh()


# ---------------------------------------------------------------- Informacion

func _build_info(tab: Tab) -> Control:
	var categories: Array = INFO_TABS[tab]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", NAV_GAP + 8)

	# Izquierda: las categorias. Moverse por ellas ya cambia el texto.
	var list := VBoxContainer.new()
	list.alignment = BoxContainer.ALIGNMENT_CENTER
	list.add_theme_constant_override("separation", 6)
	row.add_child(list)
	var buttons: Array[Button] = []
	for i in categories.size():
		var b := Button.new()
		b.text = InfoText.title(categories[i])
		b.custom_minimum_size = Vector2(250, 36)
		b.add_theme_font_size_override("font_size", 15)
		b.focus_entered.connect(_show_category.bind(tab, i))
		b.pressed.connect(_show_category.bind(tab, i))
		list.add_child(b)
		buttons.append(b)

	# Derecha: el texto, con scroll si no cabe.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	panel.add_child(scroll)

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.focus_mode = Control.FOCUS_NONE
	text.add_theme_font_size_override("normal_font_size", 14)
	scroll.add_child(text)

	var hint := _center_label(Lang.t("Av Pág / Re Pág o la rueda del ratón para desplazar el texto"), 12)
	hint.modulate = Color(1, 1, 1, 0.55)
	right.add_child(hint)
	_info_views[tab] = {"categories": categories, "buttons": buttons, "scroll": scroll, "text": text}
	return row


func _show_category(tab: Tab, i: int) -> void:
	_last_category[tab] = i
	var view: Dictionary = _info_views[tab]
	(view["text"] as RichTextLabel).text = InfoText.text(view["categories"][i])
	(view["scroll"] as ScrollContainer).scroll_vertical = 0
	var buttons: Array = view["buttons"]
	for j in buttons.size():
		if j == i:
			(buttons[j] as Button).add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
		else:
			(buttons[j] as Button).remove_theme_color_override("font_color")


# ---------------------------------------------------------------- Comun

static func _center_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	return l


static func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _refresh() -> void:
	for slot in Settings.SLOT_COUNT:
		for lane in Lanes.COUNT:
			var btn: Button = _key_buttons[slot][lane]
			var assigned := Settings.binding(slot, lane) != Settings.NO_KEY
			if _waiting_slot == slot and _waiting_lane == lane:
				btn.text = Lang.t("pulsa...")
			elif assigned:
				btn.text = Lanes.key_label(lane, slot)
			else:
				btn.text = Lang.t("- sin asignar -")
			btn.modulate = Color(1, 1, 1, 1.0 if assigned else 0.5)

	for lane in Lanes.COUNT:
		var empty := Settings.binding(Settings.SLOT_SECONDARY, lane) == Settings.NO_KEY
		_clear_buttons[lane].disabled = empty

	_offset_label.text = "%+d ms" % Settings.offset_ms

	for slot in Settings.SLOT_COUNT:
		var preset := Settings.current_preset(slot)
		if preset != "":
			_preset_labels[slot].text = Lang.t(preset)
		elif Settings.slot_is_empty(slot):
			_preset_labels[slot].text = Lang.t("ninguna")
		else:
			_preset_labels[slot].text = Lang.t("a medida")


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _on_rebind(slot: int, lane: int) -> void:
	_waiting_slot = slot
	_waiting_lane = lane
	_set_status(Lang.t("Esperando tecla para %s (%s)...") % [
		Lanes.lane_name(lane), Settings.slot_name(slot).to_lower()], Color("ffd23f"))
	_refresh()


func _on_clear(lane: int) -> void:
	_cancel_wait()
	var err := Settings.clear_binding(Settings.SLOT_SECONDARY, lane)
	if err == "":
		_set_status(Lang.t("%s se queda sin tecla secundaria") % Lanes.lane_name(lane), Color("888899"))
	else:
		_set_status(err, Color("f9393f"))
	_refresh()


func _on_preset(slot: int, preset_name: String) -> void:
	_cancel_wait()
	var err := Settings.apply_preset(slot, preset_name)
	if err == "":
		var shown := Lang.t(preset_name) if preset_name != "" else Lang.t("sin teclas")
		_set_status("%s: %s" % [Settings.slot_name(slot), shown], Color("2ee6a8"))
	else:
		_set_status(err, Color("f9393f"))
	_refresh()


func _cancel_wait() -> void:
	_waiting_slot = -1
	_waiting_lane = -1


func _go_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## Se usa _input y no _unhandled_input: mientras esperamos una tecla hay que
## capturarla antes de que nadie mas la interprete.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key := event as InputEventKey
	var view: Dictionary = _info_views.get(_last_tab, {})
	if key.echo and _waiting_slot == -1 and view.is_empty():
		return

	if _waiting_slot == -1:
		if key.keycode == KEY_ESCAPE and not key.echo:
			get_viewport().set_input_as_handled()
			_go_back()
		elif not view.is_empty() and key.keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
			get_viewport().set_input_as_handled()
			var step := SCROLL_STEP if key.keycode == KEY_PAGEDOWN else -SCROLL_STEP
			(view["scroll"] as ScrollContainer).scroll_vertical += step
		return
	if key.echo:
		return

	get_viewport().set_input_as_handled()
	var slot := _waiting_slot
	var lane := _waiting_lane
	_cancel_wait()

	if key.keycode == KEY_ESCAPE:
		_set_status(Lang.t("Cancelado"), Color("888899"))
		_refresh()
		return

	var physical := key.physical_keycode
	if physical == 0:
		physical = key.keycode

	var err := Settings.set_binding(slot, lane, physical)
	if err == "":
		_set_status("%s (%s) = %s" % [Lanes.lane_name(lane),
			Settings.slot_name(slot).to_lower(), Lanes.key_name(physical)], Color("2ee6a8"))
	else:
		_set_status(err, Color("f9393f"))
	_refresh()
