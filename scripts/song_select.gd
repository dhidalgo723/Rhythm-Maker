extends Control

## Juego Libre: lista de grabaciones. Al elegir una se pregunta si jugarla tal
## cual o con habilidades de jefe, y en ese caso cuales (tantas como se quiera).

const MENU_SCENE := "res://scenes/main_menu.tscn"
const PLAY_SCENE := "res://scenes/play_scene.tscn"
const EDIT_SCENE := "res://scenes/edit_menu.tscn"

## Columnas de la lista de habilidades.
const ABILITY_COLUMNS := 3

var _list: VBoxContainer
var _empty: Label
var _back: Button
## Pantalla de la lista, que se oculta mientras se elige como jugar.
var _main: Control
## Ventana abierta encima de la lista (null si no hay).
var _overlay: Control
var _entry: SongEntry
## Habilidades marcadas: id -> boton.
var _ability_buttons := {}
var _picked := {}
var _play_btn: Button
var _ability_desc: Label


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
	_main = margin

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
	_entry = entry
	_open_choice()


func _start(abilities: Array[String]) -> void:
	Session.selected_song = _entry
	Session.free_abilities = abilities
	get_tree().change_scene_to_file(PLAY_SCENE)


# ---------------------------------------------------------------- Ventanas

## Ventana centrada sobre la lista (que se oculta, para que el teclado no se
## escape a ella). Devuelve la columna donde poner el contenido.
func _open_overlay() -> VBoxContainer:
	_close_overlay()
	_main.visible = false
	_overlay = CenterContainer.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var panel := PanelContainer.new()
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_main.visible = true


## Primera pregunta: con o sin habilidades.
func _open_choice() -> void:
	var box := _open_overlay()
	box.add_child(_title(Lang.t("¿Cómo quieres jugar %s?") % _entry.title(), 22))
	var no := _big(Lang.t("SIN HABILIDADES"))
	no.pressed.connect(func() -> void: _start([]))
	box.add_child(no)
	var yes := _big(Lang.t("CON HABILIDADES"))
	yes.pressed.connect(_open_abilities)
	box.add_child(yes)
	var cancel := Button.new()
	cancel.text = Lang.t("Cancelar")
	cancel.custom_minimum_size = Vector2(200, 40)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_back_to_list)
	box.add_child(cancel)
	no.grab_focus.call_deferred()


## Segunda: que habilidades. Se empieza con las de la ultima vez marcadas.
func _open_abilities() -> void:
	var box := _open_overlay()
	box.add_child(_title(Lang.t("ELIGE LAS HABILIDADES"), 24))
	var hint := _title(Lang.t("Intro para marcar o desmarcar. Puedes poner tantas como quieras."), 13)
	hint.add_theme_color_override("font_color", GuiTheme.TEXT_DIM)
	box.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(930, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	_ability_buttons.clear()
	_picked.clear()
	for id in Session.free_abilities:
		_picked[id] = true
	var first: Button = null
	var groups := {
		RogueCatalog.Size.SMALL: Lang.t("Pequeñas"),
		RogueCatalog.Size.MEDIUM: Lang.t("Medianas"),
		RogueCatalog.Size.BIG: Lang.t("Grandes"),
	}
	for size in groups:
		var header := Label.new()
		header.text = groups[size]
		header.add_theme_color_override("font_color", Color("ff9f43"))
		header.add_theme_font_size_override("font_size", 15)
		list.add_child(header)
		var grid := GridContainer.new()
		grid.columns = ABILITY_COLUMNS
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 6)
		list.add_child(grid)
		for id in RogueCatalog.abilities_of_size(size):
			if id in RogueCatalog.ROGUE_ONLY_ABILITIES:
				continue
			var b := Button.new()
			b.custom_minimum_size = Vector2(290, 36)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(_toggle_ability.bind(id))
			b.focus_entered.connect(_show_ability.bind(id))
			grid.add_child(b)
			_ability_buttons[id] = b
			if first == null:
				first = b

	_ability_desc = _title("", 13)
	_ability_desc.custom_minimum_size = Vector2(930, 40)
	box.add_child(_ability_desc)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	box.add_child(row)
	_play_btn = _big("")
	_play_btn.pressed.connect(_play_with_picked)
	row.add_child(_play_btn)
	var clear := Button.new()
	clear.text = Lang.t("Quitar todas")
	clear.custom_minimum_size = Vector2(180, 40)
	clear.pressed.connect(func() -> void:
		_picked.clear()
		_refresh_abilities())
	row.add_child(clear)
	var back := Button.new()
	back.text = Lang.t("Volver")
	back.custom_minimum_size = Vector2(160, 40)
	back.pressed.connect(_open_choice)
	row.add_child(back)

	_refresh_abilities()
	first.grab_focus.call_deferred()


func _toggle_ability(id: String) -> void:
	if _picked.has(id):
		_picked.erase(id)
	else:
		_picked[id] = true
	_refresh_abilities()


func _refresh_abilities() -> void:
	for id in _ability_buttons:
		var b: Button = _ability_buttons[id]
		var on := _picked.has(id)
		b.text = "%s %s" % ["[X]" if on else "[  ]", RogueCatalog.ability_name(id)]
		if on:
			b.add_theme_color_override("font_color", GuiTheme.TEXT_FOCUS)
		else:
			b.remove_theme_color_override("font_color")
	_play_btn.text = Lang.t("JUGAR (%d)") % _picked.size()


func _show_ability(id: String) -> void:
	_ability_desc.text = "%s: %s" % [RogueCatalog.ability_name(id), RogueCatalog.ability_desc(id)]


## En el orden del catalogo, no en el que se marcaron.
func _play_with_picked() -> void:
	var out: Array[String] = []
	for id in RogueCatalog.ABILITY:
		if _picked.has(id):
			out.append(id)
	_start(out)


func _back_to_list() -> void:
	_close_overlay()
	_refresh()


static func _title(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	return l


static func _big(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BigButton"
	b.custom_minimum_size = Vector2(340, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


func _on_delete(entry: SongEntry) -> void:
	Library.delete_song(entry)
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _overlay != null:
			_back_to_list()
		else:
			get_tree().change_scene_to_file(MENU_SCENE)
