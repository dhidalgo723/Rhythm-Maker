extends Control

## Maquetas del nuevo mapa del roguelike, en dos estilos, con piezas reales del
## atlas, la fuente y el tema del juego. Guarda mockups/mapa_estilo_a.png y
## mockups/mapa_estilo_b.png. Los datos son de ejemplo (canción 2, después de
## pasar la 1).
## Correr: godot --path . --disable-vsync --resolution 1152x648 res://tests/mockup_map.tscn

const OUT_DIR := "res://mockups"

# Iconos del atlas GUI/gui retro.png.
const COIN := Rect2i(264, 95, 17, 18)
const HEART := Rect2i(747, 9, 14, 12)
const CROWN := Rect2i(783, 865, 20, 15)
const BACKPACK := Rect2i(781, 795, 50, 62)
const SIGNPOST := Rect2i(330, 133, 32, 52)
const ARROW_YELLOW := Rect2i(700, 170, 42, 23)
const SCROLL := Rect2i(781, 107, 51, 73)
const RING := Rect2i(186, 615, 44, 45)
const GEMS: Array[Rect2i] = [
	Rect2i(235, 196, 24, 23), Rect2i(260, 195, 25, 25), Rect2i(287, 197, 25, 23),
	Rect2i(313, 196, 24, 23), Rect2i(338, 196, 24, 23),
]

const AMBER := Color("f5c84a")
const CYAN := Color("4de8ff")
const GREEN := Color("2ee6a8")
const RED := Color("f9393f")

var _run: RogueRun
var _style := "a"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Lang.apply("es")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run = _example_run()
	for style in ["a", "b"]:
		_style = style
		for c in get_children():
			c.queue_free()
		await get_tree().process_frame
		_build()
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var path := "%s/mapa_estilo_%s.png" % [OUT_DIR, style]
		var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("maqueta %s -> %s" % [path, error_string(err)])
	get_tree().quit(0)


func _example_run() -> RogueRun:
	var run := RogueRun.create(RoguePool.load_pool(), 7)
	run.index = 1
	run.money = 7
	run.slot_id = "metronomo"
	run.arrows = {0: {"id": "dorada", "songs_left": 2}}
	run.pending.assign(["cuerdas"])
	run.current_boss().abilities.assign(["senuelos"])
	return run


# ---------------------------------------------------------------- Estructura

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = GuiTheme.BG if _style == "a" else Color("0e0a14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if _style == "b":
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

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	cols.add_child(_side_panel(_left_content()))
	var center := _center_panel()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(center)
	cols.add_child(_side_panel(_right_content()))

	root.add_child(_buttons())


func _title() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	if _style == "a":
		row.add_child(_icon(CROWN, 30))
		row.add_child(_label("ROGUELIKE", 44, AMBER, 8))
		row.add_child(_icon(CROWN, 30))
	else:
		# Estilo B: el titulo es la pantalla de un aparato.
		var lcd := PanelContainer.new()
		lcd.add_theme_stylebox_override("panel", GuiTheme.lcd(Color.WHITE, [40, 8, 40, 10]))
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 16)
		lcd.add_child(inner)
		inner.add_child(_icon(GEMS[1], 24))
		inner.add_child(_label("ROGUELIKE", 36, CYAN, 0))
		inner.add_child(_icon(GEMS[1], 24))
		row.add_child(lcd)
	return row


func _side_panel(content: Control) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	if _style == "a":
		panel.add_theme_stylebox_override("panel", GuiTheme.box(GuiTheme.PANEL, GuiTheme.PANEL_MARGINS,
			Color.WHITE, [26, 34, 24, 50], GuiTheme.PANEL_MID))
	else:
		panel.theme_type_variation = "InsetPanel"
	panel.add_child(content)
	return panel


func _buttons() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	var play := _big("TOCAR CANCIÓN 2", 300)
	row.add_child(play)
	row.add_child(_big("ABANDONAR", 230))
	row.add_child(_big("MENÚ PRINCIPAL", 260))
	play.grab_focus.call_deferred()
	return row


# ---------------------------------------------------------------- Izquierda

func _left_content() -> Control:
	var box := _vbox(10)
	box.add_child(_heading("TU EQUIPO"))

	box.add_child(_icon_row(COIN, 30, "MONEDAS", "%d" % _run.money, AMBER))

	# Ranura: la imagen de la mejora dentro de un aro.
	box.add_child(_small("RANURA", GuiTheme.TEXT_DIM))
	var socket := _ring(RogueArt.item_texture(RogueCatalog.ItemKind.SLOT, _run.slot_id, 58), 84)
	box.add_child(socket)
	var slot_name := _small(RogueCatalog.item_name(RogueCatalog.ItemKind.SLOT, _run.slot_id), GuiTheme.TEXT)
	slot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(slot_name)

	# Flechas: las 5 teclas; las mejoradas, con una gema debajo.
	box.add_child(_small("FLECHAS", GuiTheme.TEXT_DIM))
	var keys := HBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.add_theme_constant_override("separation", 4)
	for lane in Lanes.DISPLAY_ORDER:
		var col := _vbox(2)
		var key := KeyIcons.make_icon(lane, 38)
		if _run.arrows.has(lane):
			key.modulate = Color(RogueCatalog.ARROW[_run.arrows[lane]["id"]]["color"])
		col.add_child(key)
		var gem := _icon(GEMS[0], 14) if _run.arrows.has(lane) else Control.new()
		gem.custom_minimum_size = Vector2(38, 14)
		col.add_child(gem)
		keys.add_child(col)
	box.add_child(keys)
	box.add_child(_small("Izquierda: Flecha Dorada (2)", AMBER))

	box.add_child(_icon_row(BACKPACK, 30, "MOCHILA", "Cuerdas Nuevas", GuiTheme.TEXT))
	return box


# ---------------------------------------------------------------- Derecha

func _right_content() -> Control:
	var boss := _run.current_boss()
	var spec := boss.spec()
	var box := _vbox(10)
	box.add_child(_heading("SIGUIENTE"))
	box.add_child(_icon_row(CROWN, 24, "JEFE", boss.title(), AMBER))
	box.add_child(_icon_row(SIGNPOST, 30, "CANCIÓN", "Sin conexión", GuiTheme.TEXT))
	box.add_child(_icon_row(ARROW_YELLOW, 18, "RITMO", "%s · %s" % [
		RogueCatalog.duration_text(int(spec["duration_ms"])), RogueCatalog.speed_name(spec["speed"])],
		GuiTheme.TEXT))
	box.add_child(_icon_row(HEART, 22, "FALLOS", "%d permitidos" % boss.miss_limit(), GuiTheme.TEXT))

	var ability: String = boss.abilities[0]
	if _style == "a":
		# Pergamino lila con la habilidad, en tinta oscura.
		var scroll := PanelContainer.new()
		scroll.add_theme_stylebox_override("panel", GuiTheme.box(SCROLL, [8, 14, 8, 14],
			Color.WHITE, [16, 34, 16, 30]))
		var inner := _vbox(2)
		scroll.add_child(inner)
		inner.add_child(_label("HABILIDAD", 12, Color("4a2a66"), 0, true))
		inner.add_child(_label(RogueCatalog.ability_name(ability), 15, Color("2a1440"), 0, true))
		inner.add_child(_label(RogueCatalog.ability_desc(ability), 11, Color("4a2a66"), 0, true))
		box.add_child(scroll)
	else:
		box.add_child(_small("HABILIDAD", GuiTheme.TEXT_DIM))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_icon(GEMS[3], 20))
		row.add_child(_label(RogueCatalog.ability_name(ability), 15, RED, 3))
		box.add_child(row)
		box.add_child(_label(RogueCatalog.ability_desc(ability), 11, GuiTheme.TEXT, 3, true))
	return box


# ---------------------------------------------------------------- Centro

func _center_panel() -> Control:
	var panel := PanelContainer.new()
	var accent := AMBER if _style == "a" else CYAN
	if _style == "b":
		panel.theme_type_variation = "InsetPanel"
	var stack := Control.new()
	panel.add_child(stack)

	var box := _vbox(8)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(box)
	if _style == "b":
		var lines := _Scanlines.new()
		lines.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(lines)

	# Cabecera: el jefe que viene.
	box.add_child(_label("PRÓXIMO JEFE", 13, GuiTheme.TEXT_DIM, 0, true))
	box.add_child(_label("JEFE MEDIANO  ·  CANCIÓN 2 DE 10", 22, accent, 4, true))
	box.add_child(_progress_strip(accent))
	box.add_child(_label("Objetivo: 4.300 puntos  ·  Si la pasas: hasta 10 monedas", 13, GuiTheme.TEXT, 3, true))

	box.add_child(_rule(accent))
	box.add_child(_label("ÚLTIMA CANCIÓN  ·  JEFE PEQUEÑO", 14, GuiTheme.TEXT_DIM, 0, true))
	box.add_child(_stat("PRECISIÓN", "94,3 %", 94.3, GREEN))
	box.add_child(_stat("FALLOS", "3 / 15", 3.0 / 15.0 * 100.0, RED))
	box.add_child(_stat("PUNTUACIÓN", "5.120 / 3.400", 100.0, accent))
	box.add_child(_stat_text("PERFECTOS · COMBO", "31 · 22"))
	box.add_child(_stat_text("DINERO GANADO", "+7 monedas"))

	box.add_child(_rule(accent))
	box.add_child(_label("PARTIDA", 14, GuiTheme.TEXT_DIM, 0, true))
	box.add_child(_stat_text("JEFES SUPERADOS", "1 de 10"))
	box.add_child(_stat_text("VUELTA", "1 de 3  (fallos x1,0)"))
	return panel


func _progress_strip(accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var letters: Array[String] = ["P", "M", "G", "P", "M", "G", "P", "M", "G", "J"]
	for i in 10:
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(44, 40)
		var sb := GuiTheme.lcd(Color.WHITE, [2, 2, 2, 2])
		if i == _run.index:
			sb = GuiTheme.lcd(GuiTheme.FOCUS_TINT, [2, 2, 2, 2])
		chip.add_theme_stylebox_override("panel", sb)
		var color := GREEN if i < _run.index else (accent if i == _run.index else GuiTheme.TEXT_DIM)
		var text := "OK" if i < _run.index else letters[i]
		var l := _label("%d\n%s" % [i + 1, text], 11, color, 0, true)
		chip.add_child(l)
		row.add_child(chip)
	return row


func _stat(title: String, value: String, percent: float, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_l := _label(title, 14, GuiTheme.TEXT, 3)
	name_l.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.value = percent
	bar.custom_minimum_size = Vector2(0, 20)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _style == "b":
		# Estilo B: barras de vumetro planas, del color del dato.
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
	row.add_child(_label(value, 14, AMBER if _style == "a" else CYAN, 3))
	return row


func _rule(color: Color) -> Control:
	var r := ColorRect.new()
	r.color = Color(color, 0.35)
	r.custom_minimum_size = Vector2(0, 2)
	return r


# ---------------------------------------------------------------- Piezas

func _heading(text: String) -> Label:
	var l := _label(text, 17, AMBER if _style == "a" else CYAN, 4, true)
	return l


func _icon_row(region: Rect2i, px: int, title: String, value: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(44, 40)
	if _style == "b":
		holder.add_child(_ring(null, 44))
		var ic := _icon(region, px)
		ic.position = Vector2(22, 20) - ic.custom_minimum_size / 2
		holder.get_child(0).add_child(ic)
	else:
		holder.add_child(_icon(region, px))
	row.add_child(holder)
	var col := _vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_small(title, GuiTheme.TEXT_DIM))
	var value_l := _label(value, 14, color, 3, false)
	value_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(value_l)
	row.add_child(col)
	return row


## Aro del atlas con algo dentro (o vacio).
func _ring(content: Texture2D, px: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px, px)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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


func _icon(region: Rect2i, px: int) -> TextureRect:
	var scale := maxi(1, roundi(float(px) / region.size.y))
	var t := TextureRect.new()
	t.texture = GuiTheme.piece(region, scale)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.custom_minimum_size = Vector2(region.size) * scale
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


func _big(text: String, width: int) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BigButton"
	b.custom_minimum_size = Vector2(width, 54)
	b.add_theme_font_size_override("font_size", 18)
	return b


func _small(text: String, color: Color) -> Label:
	return _label(text, 11, color, 2)


func _label(text: String, size: int, color: Color, outline: int, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	# Solo los centrados ajustan linea: van en columnas que les dan el ancho.
	# Dentro de una fila horizontal, una etiqueta con ajuste se queda sin ancho.
	if center:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


## Estilo B: rayas horizontales suaves, como la carcasa de un equipo de musica.
class _Stripes extends Control:
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for y in range(0, int(size.y), 4):
			draw_rect(Rect2(0, y, size.x, 2), Color(1, 1, 1, 0.025))


## Estilo B: lineas de barrido de pantalla sobre el centro.
class _Scanlines extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for y in range(0, int(size.y), 3):
			draw_rect(Rect2(0, y, size.x, 1), Color(0, 0, 0, 0.28))
