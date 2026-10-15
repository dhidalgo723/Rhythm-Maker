extends Control

## Venta de garaje: la foto de la tienda con tres cajas en la mesa.
##   - Caja izquierda: siempre un consumible.
##   - Caja central: 9 de cada 10 veces una mejora de ranura, si no una de flecha.
##   - Caja derecha: 7 de cada 10 veces una mejora de flecha, si no una de ranura.
## Lo comprado deja una X roja en su caja: no se repone.

const ROGUE_SCENE := "res://scenes/rogue_menu.tscn"
const PLAY_SCENE := "res://scenes/play_scene.tscn"
const PHOTO := "res://roguelike/img/Tienda.jpg"

## Tamano de la foto y centro del fondo de cada caja, en pixeles de la foto.
## Medidos sobre la imagen.
const PHOTO_SIZE := Vector2(1264, 843)
const BOX_CENTERS: Array[Vector2] = [Vector2(580, 430), Vector2(730, 430), Vector2(882, 430)]
## Zona clicable de cada caja, en pixeles de la foto (el objeto sobresale por arriba).
const BOX_HIT := Vector2(150, 175)
## Lado maximo del objeto dentro de la caja, en pixeles de pantalla.
const ITEM_PX := 112

const KIND_COLORS := {
	RogueCatalog.ItemKind.SLOT: Color("4de8ff"),
	RogueCatalog.ItemKind.ARROW: Color("2ee6a8"),
	RogueCatalog.ItemKind.CONSUMABLE: Color("ff9f43"),
}


## Aspa roja grande que tapa la caja de un objeto ya comprado.
class SoldMark extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-size.x * 0.06)
		for pass_i in 2:
			var w := 24.0 if pass_i == 0 else 14.0
			var c := Color("3a0606") if pass_i == 0 else Color("e8262b")
			draw_line(r.position, r.end, c, w)
			draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), c, w)


var _run: RogueRun
var _photo: TextureRect
var _boxes: Array[Button] = []
var _items: Array[TextureRect] = []
var _marks: Array[SoldMark] = []
var _money_label: Label
var _info_kind: Label
var _info_name: Label
var _info_desc: Label
var _info_price: Label
var _status: Label
var _inventory: Label
var _bottom: HBoxContainer
var _next_btn: Button
var _abandon_btn: Button
var _lane_picker: PanelContainer
var _picker_offer := -1
var _abandon_armed := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_run = Session.rogue_run
	if _run == null or _run.state != RogueRun.State.SHOP:
		set_process(false)
		get_tree().change_scene_to_file.call_deferred(ROGUE_SCENE)
		return

	var bg := ColorRect.new()
	bg.color = GuiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_photo = TextureRect.new()
	_photo.texture = load(PHOTO) if ResourceLoader.exists(PHOTO) else null
	_photo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Es una foto reducida, no pixel art: con filtro lineal no hace dientes.
	_photo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_photo)

	for i in RogueCatalog.SHOP_BOXES.size():
		_build_box(i)

	_build_top()
	_build_bottom()
	_build_lane_picker()

	resized.connect(_layout)
	_refresh()
	_layout()
	_focus_first_box()


# ---------------------------------------------------------------- Construccion

func _build_box(i: int) -> void:
	var b := Button.new()
	b.flat = true
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, empty)
	b.pressed.connect(_on_box_pressed.bind(i))
	b.focus_entered.connect(_on_box_focus.bind(i, true))
	b.focus_exited.connect(_on_box_focus.bind(i, false))
	add_child(b)
	_boxes.append(b)

	var item := RogueArt.make_rect(null)
	item.stretch_mode = TextureRect.STRETCH_KEEP
	b.add_child(item)
	_items.append(item)

	var mark := SoldMark.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = false
	b.add_child(mark)
	_marks.append(mark)


func _build_top() -> void:
	_money_label = _label("", 24, GuiTheme.TEXT_FOCUS)
	_money_label.autowrap_mode = TextServer.AUTOWRAP_OFF   # sin ancho fijo: no partir
	_money_label.position = Vector2(18, 12)
	_money_label.add_theme_constant_override("outline_size", 8)
	add_child(_money_label)

	# Descripcion del objeto seleccionado, arriba, sobre la pared.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 8
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# La pantalla de casete a la mitad de tamano que los demas paneles: aqui
	# solo hay unas lineas de texto y tapaba media pared de la tienda.
	if GuiTheme.available():
		panel.add_theme_stylebox_override("panel", GuiTheme.box(GuiTheme.PANEL,
			GuiTheme.PANEL_MARGINS, Color.WHITE, [22, 20, 20, 28], GuiTheme.PANEL_MID, 1))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	_info_kind = _label("", 11, GuiTheme.TEXT_DIM)
	_info_name = _label("", 16, GuiTheme.TEXT_FOCUS)
	_info_desc = _label("", 12, GuiTheme.TEXT)
	_info_price = _label("", 12, GuiTheme.TEXT)
	for l in [_info_kind, _info_name, _info_desc, _info_price]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)


func _build_bottom() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_top = -118
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	_status = _label("", 16, GuiTheme.TEXT_FOCUS)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_constant_override("outline_size", 6)
	col.add_child(_status)
	_inventory = _label("", 14, GuiTheme.TEXT)
	_inventory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inventory.add_theme_constant_override("outline_size", 6)
	col.add_child(_inventory)

	_bottom = HBoxContainer.new()
	_bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom.add_theme_constant_override("separation", 22)
	col.add_child(_bottom)
	_next_btn = _plank(Lang.t("Siguiente jefe (canción %d)") % (_run.index + 1), _on_next)
	_bottom.add_child(_next_btn)
	_bottom.add_child(_plank(Lang.t("Ver la partida"), _on_map))
	_abandon_btn = _plank(Lang.t("Abandonar partida"), _on_abandon)
	_bottom.add_child(_abandon_btn)
	for b in _bottom.get_children():
		(b as Button).focus_entered.connect(_show_summary)


## Coloca cada caja encima de su caja de la foto. La foto se escala para
## cubrir la pantalla: hay que hacer la misma cuenta que hace el TextureRect.
func _layout() -> void:
	var scale := maxf(size.x / PHOTO_SIZE.x, size.y / PHOTO_SIZE.y)
	var origin := (size - PHOTO_SIZE * scale) * 0.5
	var hit := BOX_HIT * scale
	for i in _boxes.size():
		var bottom_center := origin + BOX_CENTERS[i] * scale
		_boxes[i].position = Vector2(bottom_center.x - hit.x * 0.5, bottom_center.y - hit.y)
		_boxes[i].size = hit
		_marks[i].position = Vector2(hit.x * 0.05, hit.y * 0.32)
		_marks[i].size = Vector2(hit.x * 0.9, hit.y * 0.68)
		_place_item(i)


## El objeto se apoya en el fondo de la caja, centrado, y sobresale por arriba.
func _place_item(i: int) -> void:
	var item := _items[i]
	var hit := _boxes[i].size
	var tex_size := item.texture.get_size() if item.texture != null else Vector2.ZERO
	item.size = tex_size
	item.position = Vector2((hit.x - tex_size.x) * 0.5, hit.y - tex_size.y - hit.y * 0.04).round()


func _refresh() -> void:
	_money_label.text = Lang.t("Monedas: %d") % _run.money
	for i in _boxes.size():
		var offer: Dictionary = _run.offers[i]
		var sold: bool = offer["sold"]
		_items[i].visible = not sold
		_marks[i].visible = sold
		_marks[i].queue_redraw()
		if not sold:
			_items[i].texture = RogueArt.item_texture(offer["kind"], offer["id"], ITEM_PX)
		_place_item(i)
	_inventory.text = _inventory_text()
	var index := _boxes.find(get_viewport().gui_get_focus_owner())
	if index != -1:
		_show_offer(index)
	else:
		_show_summary()


func _focus_first_box() -> void:
	for i in _boxes.size():
		if not _run.offers[i]["sold"]:
			_boxes[i].grab_focus.call_deferred()
			return
	_next_btn.grab_focus.call_deferred()


# ---------------------------------------------------------------- Informacion

func _on_box_focus(i: int, focused: bool) -> void:
	RogueArt.set_selected(_items[i], focused)
	if focused:
		_show_offer(i)


func _show_offer(i: int) -> void:
	var offer: Dictionary = _run.offers[i]
	var kind: RogueCatalog.ItemKind = offer["kind"]
	_info_kind.text = RogueCatalog.kind_name(kind)
	_info_kind.add_theme_color_override("font_color", KIND_COLORS[kind])
	_info_name.text = RogueCatalog.item_name(kind, offer["id"])
	_info_desc.text = RogueCatalog.item_desc(kind, offer["id"])
	var price := _run.price(offer)
	if offer["sold"]:
		_info_price.text = Lang.t("Comprado")
	elif price > _run.money:
		_info_price.text = Lang.t("%d monedas — no te llega") % price
	else:
		_info_price.text = Lang.t("%d monedas — Intro para comprar") % price


func _show_summary() -> void:
	_info_kind.text = Lang.t("Venta de garaje")
	_info_kind.add_theme_color_override("font_color", GuiTheme.TEXT_DIM)
	_info_name.text = Lang.t("Siguiente: %s") % _run.current_boss().title()
	_info_desc.text = RogueCatalog.size_summary(_run.current_boss().size)
	_info_price.text = Lang.t("Elige una caja para ver qué hay")


func _inventory_text() -> String:
	var slot: String = RogueCatalog.item_name(RogueCatalog.ItemKind.SLOT, _run.slot_id) if _run.slot_id != "" else Lang.t("vacía")
	var arrows: Array[String] = []
	for lane in Lanes.DISPLAY_ORDER:
		var id := _run.arrow_on(lane)
		if id != "":
			arrows.append("%s: %s" % [Lanes.lane_name(lane), RogueCatalog.item_name(RogueCatalog.ItemKind.ARROW, id)])
	var parts: Array[String] = [Lang.t("Ranura: %s") % slot]
	parts.append(Lang.t("Flechas: %s") % (", ".join(arrows) if not arrows.is_empty() else Lang.t("ninguna")))
	var pending: Array[String] = []
	for id in _run.pending:
		pending.append(RogueCatalog.item_name(RogueCatalog.ItemKind.CONSUMABLE, id))
	if not pending.is_empty():
		parts.append(Lang.t("Siguiente canción: %s") % ", ".join(pending))
	return "   |   ".join(parts)


# ---------------------------------------------------------------- Comprar

func _on_box_pressed(i: int) -> void:
	var offer: Dictionary = _run.offers[i]
	if offer["sold"]:
		_status.text = Lang.t("Ya lo compraste")
		return
	if _run.price(offer) > _run.money:
		_status.text = Lang.t("No tienes dinero suficiente")
		return
	if offer["kind"] == RogueCatalog.ItemKind.ARROW:
		_open_lane_picker(i)
		return
	_finish_buy(i, -1)


func _finish_buy(index: int, lane: int) -> void:
	var offer: Dictionary = _run.offers[index]
	var item_name: String = RogueCatalog.item_name(offer["kind"], offer["id"])
	var replaced := _run.slot_id if offer["kind"] == RogueCatalog.ItemKind.SLOT else ""
	var err := _run.buy(index, lane)
	if err != "":
		_status.text = err
		return
	if offer["id"] == "setlist":
		var names: Array[String] = []
		for id in _run.current_boss().abilities:
			names.append(RogueCatalog.ability_name(id))
		_status.text = Lang.t("Setlist: el siguiente jefe trae %s. Las cajas se han renovado.") % ", ".join(names)
	elif replaced != "":
		_status.text = Lang.t("%s sustituye a %s en la ranura") % [item_name, RogueCatalog.item_name(RogueCatalog.ItemKind.SLOT, replaced)]
	elif lane != -1:
		_status.text = Lang.t("%s puesta en %s") % [item_name, Lanes.lane_name(lane)]
	else:
		_status.text = Lang.t("Has comprado %s") % item_name
	_refresh()


# ---------------------------------------------------------------- Elegir flecha

func _build_lane_picker() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_lane_picker = PanelContainer.new()
	_lane_picker.visible = false
	center.add_child(_lane_picker)


func _open_lane_picker(offer_index: int) -> void:
	_picker_offer = offer_index
	for c in _lane_picker.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_lane_picker.add_child(box)
	var arrow_name: String = RogueCatalog.item_name(RogueCatalog.ItemKind.ARROW, _run.offers[offer_index]["id"])
	var title := _label(Lang.t("¿En qué flecha pones la %s?") % arrow_name, 18, GuiTheme.TEXT_FOCUS)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	box.add_child(row)
	var first: Button = null
	for lane in Lanes.DISPLAY_ORDER:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		row.add_child(col)
		var b := Button.new()
		b.icon = KeyIcons.texture(lane, KeyIcons.Variant.NORMAL, true)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(84, 84)
		b.tooltip_text = Lanes.lane_name(lane)
		b.pressed.connect(_on_lane_chosen.bind(lane))
		col.add_child(b)
		var current := _run.arrow_on(lane)
		var extra := "\n(%s)" % RogueCatalog.item_name(RogueCatalog.ItemKind.ARROW, current) if current != "" else ""
		var info := _label(Lanes.lane_name(lane) + extra, 12, GuiTheme.TEXT_DIM)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.custom_minimum_size = Vector2(84, 0)
		col.add_child(info)
		if first == null:
			first = b

	var cancel := Button.new()
	cancel.text = Lang.t("Cancelar")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.custom_minimum_size = Vector2(180, 40)
	cancel.pressed.connect(_close_lane_picker)
	box.add_child(cancel)

	_lane_picker.visible = true
	_set_shop_visible(false)
	first.grab_focus.call_deferred()


func _on_lane_chosen(lane: int) -> void:
	var index := _picker_offer
	_close_lane_picker()
	_finish_buy(index, lane)


func _close_lane_picker() -> void:
	var index := _picker_offer
	_lane_picker.visible = false
	_picker_offer = -1
	_set_shop_visible(true)
	if index != -1:
		_boxes[index].grab_focus.call_deferred()


## Mientras se elige flecha, ni las cajas ni los botones deben poder pulsarse.
func _set_shop_visible(value: bool) -> void:
	for b in _boxes:
		b.visible = value
	_bottom.visible = value


# ---------------------------------------------------------------- Botones

func _on_next() -> void:
	_run.state = RogueRun.State.MAP
	var prepared := _run.prepare_song()
	if prepared == null:
		_run.state = RogueRun.State.SHOP
		_status.text = Lang.t("No se pudo preparar la siguiente canción")
		return
	Session.rogue_prepared = prepared
	Session.selected_song = null
	get_tree().change_scene_to_file(PLAY_SCENE)


func _on_map() -> void:
	_run.state = RogueRun.State.MAP
	get_tree().change_scene_to_file(ROGUE_SCENE)


## Abandonar pide confirmacion: un toque de mas no debe tirar la partida.
func _on_abandon() -> void:
	if not _abandon_armed:
		_abandon_armed = true
		_abandon_btn.text = Lang.t("¿Seguro? Pulsa otra vez")
		_status.text = Lang.t("Abandonar borra la partida entera")
		return
	Session.rogue_run = null
	get_tree().change_scene_to_file(ROGUE_SCENE)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _lane_picker.visible:
			_close_lane_picker()


# ---------------------------------------------------------------- Ayudas

static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _plank(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BigButton"
	b.custom_minimum_size = Vector2(240, 50)
	b.pressed.connect(on_press)
	return b
