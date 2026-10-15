class_name GuiTheme
extends RefCounted

## Tema visual de toda la interfaz, construido con piezas del atlas de pixel art
## GUI/gui retro.png. Estilo de aparato retro tipo walkman: paneles con forma de
## pantalla de casete, botones grandes como teclas de pildora y textos en
## amarillo de pantalla LCD.
##
## Cada pieza se recorta del atlas y se reescala UNA vez a una escala entera
## con vecino mas proximo: asi los bordes del 9-slice se dibujan pixel a pixel
## y no salen borrosos ni con pixeles de distinto tamano.
##
## Sin el atlas (p. ej. alguien clona el repo sin la carpeta GUI/) se devuelve
## un tema que solo pone colores: el juego sigue funcionando con los controles
## por defecto de Godot.

const ATLAS_PATH := "res://GUI/gui retro.png"
## Tipografia de toda la interfaz: la copia con tildes y ñ que genera
## tools/font_add_accents.py, o la original si no se ha generado. Lo que siga
## faltando (flechas...) sale de la fuente por defecto de Godot (ver _font()).
const FONT_PATHS: Array[String] = [
	"res://Fonts/After Burner Neue Acentos.ttf",
	"res://Fonts/After Burner Neue.ttf",
]
const SCALE := 2
## Las teclas de pildora miden 13 px de alto: a x4 tienen la altura de un boton
## de menu y las esquinas siguen siendo redondas en vez de estirarse.
const PILL_SCALE := 4

# --- Paleta (sacada del morado de la carcasa y el amarillo de las teclas) ---
const BG := Color("120c18")
const TEXT := Color("efe6ff")
const TEXT_DIM := Color("a996c8")
const TEXT_FOCUS := Color("f5c84a")
const TEXT_DISABLED := Color("5d4c74")
## Texto sobre la tecla amarilla: oscuro, el blanco no se leeria.
const TEXT_ON_KEY := Color("2a1440")
const OUTLINE := Color("0c0812")
const BODY_DARK := Color("2a1b3d")
const BODY_LIGHT := Color("7a4fa0")

# --- Piezas del atlas ---
# Cada pieza lleva sus margenes 9-slice [izq, arriba, der, abajo] en pixeles del
# atlas, que cubren lo que no debe estirarse (tornillos, esquinas, la pestana
# amarilla y el hueco de la cinta del casete). Las que tienen adornos en mitad
# de un canto llevan tambien un MID: la columna y la fila (de 2 px) que se
# estiran en lugar del centro real de la pieza. Ver _sliced().

## Pantalla con carcasa de casete: paneles. La pestana de arriba es la tecla de
## grabar; abajo, el hueco de la cinta con sus tornillos.
const PANEL := Rect2i(433, 369, 93, 78)
const PANEL_MARGINS := [28, 16, 22, 24]
const PANEL_MID := Vector2i(39, 35)
## Placa oscura con un tornillo en cada esquina: listas y recuadros interiores.
const INSET := Rect2i(5, 611, 96, 39)
const INSET_MARGINS := [9, 9, 9, 9]
## Visor de LCD con marco morado: botones normales y campos de texto.
const FRAME_BUTTON := Rect2i(261, 4, 75, 31)
const FRAME_BUTTON_MARGINS := [8, 8, 8, 8]
## A x1: a x2 el marco se come casi toda la altura de un boton de una linea.
const FRAME_SCALE := 1
## Teclas de pildora: botones grandes de menu y la pista del slider.
const PILL_PURPLE := Rect2i(156, 878, 52, 13)
const PILL_YELLOW := Rect2i(156, 903, 52, 15)
const PILL_DARK := Rect2i(91, 904, 52, 13)
const PILL_MARGINS := [7, 6, 7, 6]
## Barra de progreso vacia, y el relleno rosa que va dentro.
const BAR_TRACK := Rect2i(779, 951, 50, 10)
const BAR_TRACK_MARGINS := [6, 4, 6, 4]
const BAR_FILL := Rect2i(784, 940, 24, 5)
## Posicion del relleno dentro de la pista.
const BAR_FILL_OFFSET := Vector2i(4, 2)
## Bolitas: tirador del slider (y el pulso de la calibracion).
const KNOB := Rect2i(494, 301, 11, 11)
const KNOB_FOCUS := Rect2i(469, 288, 11, 11)
const KNOB_DARK := Rect2i(482, 301, 11, 11)
## Triangulo amarillo, como el de "play": cursor que senala lo seleccionado.
const CURSOR := Rect2i(417, 273, 10, 13)
const CURSOR_SCALE := SCALE   # mismo tamano de pixel que el resto

## Tintes de estado. Los mayores que 1 aclaran la textura.
const HOVER_TINT := Color(1.2, 1.12, 1.25)
const FOCUS_TINT := Color(1.45, 1.3, 1.55)
const PRESSED_TINT := Color(0.8, 0.75, 0.82)
const DISABLED_TINT := Color(0.55, 0.52, 0.6, 0.75)

const NO_MID := Vector2i(-1, -1)

static var _atlas: Image
static var _cache := {}


static func available() -> bool:
	return _atlas_image() != null


## Una pieza del atlas, recortada y reescalada (cacheada).
static func piece(region: Rect2i, scale: int = SCALE) -> Texture2D:
	var key := "%s@%d" % [region, scale]
	if _cache.has(key):
		return _cache[key]
	var img := _atlas_image()
	if img == null:
		return null
	var sub := img.get_region(region)
	sub.resize(region.size.x * scale, region.size.y * scale, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(sub)
	_cache[key] = tex
	return tex


## StyleBox 9-slice de una pieza. `content` = margenes interiores para el texto
## [izq, arriba, der, abajo] en pixeles de pantalla. `mid` = columna y fila que
## se estiran (NO_MID: las del centro de la pieza).
static func box(region: Rect2i, margins: Array, tint: Color = Color.WHITE,
		content: Array = [], mid: Vector2i = NO_MID, scale: int = SCALE) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _sliced(region, margins, mid, scale)
	sb.texture_margin_left = margins[0] * scale
	sb.texture_margin_top = margins[1] * scale
	sb.texture_margin_right = margins[2] * scale
	sb.texture_margin_bottom = margins[3] * scale
	sb.modulate_color = tint
	if not content.is_empty():
		sb.content_margin_left = content[0]
		sb.content_margin_top = content[1]
		sb.content_margin_right = content[2]
		sb.content_margin_bottom = content[3]
	return sb


## La pieza con el centro sustituido por una tira de 2 px de `mid`: los cantos
## se conservan enteros y lo unico que se estira es esa tira lisa. Asi un
## tornillo o el hueco de la cinta en mitad de un canto no se deforman al
## estirar el panel. Estirar una tira lisa tampoco deja costuras, que es lo que
## pasaba al repetir (tile) el centro.
static func _sliced(region: Rect2i, margins: Array, mid: Vector2i, scale: int) -> Texture2D:
	var key := "%s|%s|%s@%d" % [region, margins, mid, scale]
	if _cache.has(key):
		return _cache[key]
	var img := _atlas_image()
	if img == null:
		return null
	var w := region.size.x
	var h := region.size.y
	var l: int = margins[0]
	var t: int = margins[1]
	var r: int = margins[2]
	var b: int = margins[3]
	var mx := mid.x if mid.x >= 0 else w / 2 - 1
	var my := mid.y if mid.y >= 0 else h / 2 - 1
	# Tramos [origen, ancho] de la pieza que se copian, en orden.
	var cols := [[0, l], [mx, 2], [w - r, r]]
	var rows := [[0, t], [my, 2], [h - b, b]]

	var out := Image.create_empty(l + 2 + r, t + 2 + b, false, Image.FORMAT_RGBA8)
	var dy := 0
	for row in rows:
		var dx := 0
		for col in cols:
			var src := Rect2i(region.position + Vector2i(col[0], row[0]), Vector2i(col[1], row[1]))
			out.blit_rect(img, src, Vector2i(dx, dy))
			dx += col[1]
		dy += row[1]
	out.resize(out.get_width() * scale, out.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(out)
	_cache[key] = tex
	return tex


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var font := _font()
	if font != null:
		t.default_font = font

	for type in ["Label", "Button", "LineEdit"]:
		t.set_color("font_outline_color", type, OUTLINE)
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("outline_size", "Label", 3)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", OUTLINE)
	t.set_constant("outline_size", "RichTextLabel", 3)

	_button_colors(t, "Button")
	t.set_constant("outline_size", "Button", 4)

	# Las teclas grandes existen aunque no haya atlas, para que las escenas
	# puedan pedir la variacion sin comprobar nada.
	t.set_type_variation("BigButton", "Button")
	t.set_font_size("font_size", "BigButton", 22)

	if not available():
		return t

	# --- Botones normales: visor de LCD ---
	var btn_content := [16, 6, 16, 6]
	t.set_stylebox("normal", "Button", lcd(Color.WHITE, btn_content))
	t.set_stylebox("hover", "Button", lcd(HOVER_TINT, btn_content))
	t.set_stylebox("pressed", "Button", lcd(PRESSED_TINT, btn_content))
	t.set_stylebox("hover_pressed", "Button", lcd(PRESSED_TINT, btn_content))
	t.set_stylebox("disabled", "Button", lcd(DISABLED_TINT, btn_content))
	# El foco se dibuja ENCIMA del estado normal: el marco iluminado tapa el
	# normal y, con el texto en amarillo LCD, deja claro que esta seleccionado.
	t.set_stylebox("focus", "Button", lcd(FOCUS_TINT, btn_content))

	# --- Botones grandes de menu: teclas de pildora del walkman ---
	# Variacion de tipo: se usa con `button.theme_type_variation = "BigButton"`.
	# En reposo la tecla es morada; la seleccionada se enciende en amarillo.
	var key_content := [36, 8, 36, 8]
	var purple := box(PILL_PURPLE, PILL_MARGINS, Color.WHITE, key_content, NO_MID, PILL_SCALE)
	var yellow := box(PILL_YELLOW, PILL_MARGINS, Color.WHITE, key_content, NO_MID, PILL_SCALE)
	t.set_stylebox("normal", "BigButton", purple)
	t.set_stylebox("hover", "BigButton", yellow)
	t.set_stylebox("focus", "BigButton", yellow)
	t.set_stylebox("pressed", "BigButton",
		box(PILL_YELLOW, PILL_MARGINS, PRESSED_TINT, key_content, NO_MID, PILL_SCALE))
	t.set_stylebox("hover_pressed", "BigButton",
		box(PILL_YELLOW, PILL_MARGINS, PRESSED_TINT, key_content, NO_MID, PILL_SCALE))
	t.set_stylebox("disabled", "BigButton",
		box(PILL_DARK, PILL_MARGINS, Color.WHITE, key_content, NO_MID, PILL_SCALE))
	t.set_color("font_color", "BigButton", TEXT)
	for state in ["font_hover_color", "font_focus_color", "font_hover_pressed_color", "font_pressed_color"]:
		t.set_color(state, "BigButton", TEXT_ON_KEY)
	t.set_color("font_disabled_color", "BigButton", TEXT_DISABLED)
	# Sin contorno: el texto oscuro sobre la tecla amarilla ya se lee, y un
	# contorno negro lo emborronaria.
	t.set_constant("outline_size", "BigButton", 0)

	# --- Paneles: pantalla con carcasa de casete ---
	# El contenido va dentro de la pantalla negra, no encima de la carcasa.
	var panel := box(PANEL, PANEL_MARGINS, Color.WHITE, [36, 40, 34, 56], PANEL_MID)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", box(INSET, INSET_MARGINS, Color.WHITE, [16, 14, 16, 14]))

	# --- Campos de texto: el visor de LCD, algo mas apagado que un boton ---
	var field := [14, 6, 14, 6]
	var field_tint := Color(0.85, 0.8, 0.9)
	t.set_stylebox("normal", "LineEdit", lcd(field_tint, field))
	t.set_stylebox("focus", "LineEdit", lcd(FOCUS_TINT, field))
	t.set_stylebox("read_only", "LineEdit", lcd(DISABLED_TINT, field))
	t.set_color("font_color", "LineEdit", TEXT_FOCUS)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", TEXT_FOCUS)
	t.set_color("selection_color", "LineEdit", Color(TEXT_FOCUS, 0.35))

	# --- Barra de progreso ---
	t.set_stylebox("background", "ProgressBar", box(BAR_TRACK, BAR_TRACK_MARGINS))
	t.set_stylebox("fill", "ProgressBar", _bar_fill_box())

	# --- Slider: pista de pildora oscura, lo recorrido en amarillo ---
	t.set_stylebox("slider", "HSlider", box(PILL_DARK, PILL_MARGINS))
	t.set_stylebox("grabber_area", "HSlider", box(PILL_YELLOW, PILL_MARGINS))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(PILL_YELLOW, PILL_MARGINS, HOVER_TINT))
	t.set_icon("grabber", "HSlider", piece(KNOB))
	t.set_icon("grabber_highlight", "HSlider", piece(KNOB_FOCUS))
	t.set_icon("grabber_disabled", "HSlider", piece(KNOB_DARK))

	# --- Barras de scroll: el atlas no tiene piezas verticales, se imitan ---
	t.set_stylebox("scroll", "VScrollBar", _flat(BODY_DARK, 6))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var c := BODY_LIGHT if state == "grabber" else BODY_LIGHT.lightened(0.25)
		t.set_stylebox(state, "VScrollBar", _flat(c, 6))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TooltipPanel", _flat(BODY_DARK, 4))
	t.set_color("font_color", "TooltipLabel", TEXT)

	return t


## Visor de LCD: botones normales, campos de texto y pads de la grabacion.
static func lcd(tint: Color, content: Array = []) -> StyleBoxTexture:
	return box(FRAME_BUTTON, FRAME_BUTTON_MARGINS, tint, content, NO_MID, FRAME_SCALE)


static func _button_colors(t: Theme, type: String) -> void:
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, TEXT_FOCUS)
	t.set_color("font_focus_color", type, TEXT_FOCUS)
	t.set_color("font_hover_pressed_color", type, TEXT_FOCUS)
	t.set_color("font_pressed_color", type, TEXT_DIM)
	t.set_color("font_disabled_color", type, TEXT_DISABLED)


## El relleno se dibuja a la altura completa de la barra, asi que su textura
## lleva el hueco transparente alrededor: el rosa queda dentro de la pista.
static func _bar_fill_box() -> StyleBoxTexture:
	var img := _atlas_image()
	var w := BAR_FILL.size.x + BAR_FILL_OFFSET.x * 2
	var h := BAR_TRACK.size.y
	var fill := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	fill.blit_rect(img, BAR_FILL, BAR_FILL_OFFSET)
	fill.resize(w * SCALE, h * SCALE, Image.INTERPOLATE_NEAREST)

	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(fill)
	# Izquierda: el hueco y el remate del rosa; el resto del rosa se estira.
	sb.texture_margin_left = (BAR_FILL_OFFSET.x + 2) * SCALE
	sb.texture_margin_right = BAR_FILL_OFFSET.x * SCALE
	sb.texture_margin_top = BAR_FILL_OFFSET.y * SCALE
	sb.texture_margin_bottom = (h - BAR_FILL_OFFSET.y - BAR_FILL.size.y) * SCALE
	return sb


static func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb


## La fuente del juego, con la de Godot como respaldo para los caracteres que
## le faltan. null si no esta el archivo: se queda la fuente por defecto.
static func _font() -> Font:
	var main: Font = null
	for path in FONT_PATHS:
		if ResourceLoader.exists(path):
			main = load(path)
			break
	if main == null:
		return null
	# Variacion en vez de tocar el recurso importado: el respaldo se apunta
	# aqui y el .ttf queda como esta.
	var font := FontVariation.new()
	font.base_font = main
	font.fallbacks = [ThemeDB.fallback_font]
	# Las letras quedan altas en la linea (la fuente reserva mucho hueco bajo
	# la base para descendentes que no tiene): se bajan 0.15 em para que el
	# texto salga centrado en los botones.
	font.variation_transform = Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(0, 0.15))
	return font


static func _atlas_image() -> Image:
	if _atlas == null and ResourceLoader.exists(ATLAS_PATH):
		var tex: Texture2D = load(ATLAS_PATH)
		if tex != null:
			var img := tex.get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			_atlas = img
	return _atlas
