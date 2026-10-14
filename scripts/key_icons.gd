class_name KeyIcons
extends RefCounted

## Iconos de teclas sacados del atlas de Vryell (carpeta Keys/).
##
## El atlas es una rejilla de celdas de 16x16 px. Cada tecla tiene cuatro
## variantes en columnas consecutivas, en el orden de Variant.
##
## Si el atlas no esta (p. ej. alguien clona el repo sin la carpeta Keys/),
## available() devuelve false y quien dibuja usa su forma de reserva. El juego
## sigue siendo jugable sin los graficos.

const DARK_PATH := "res://Keys/Controllers and Keyboard/kb_dark_all.png"
const LIGHT_PATH := "res://Keys/Controllers and Keyboard/kb_light_all.png"
const CELL := 16

enum Variant {
	NORMAL,           ## tecla levantada
	OUTLINE,          ## levantada, con contorno blanco
	PRESSED,          ## hundida
	PRESSED_OUTLINE,  ## hundida, con contorno blanco
}

## Esquina superior izquierda de la variante NORMAL, por id de carril.
const LANE_CELLS: Array[Vector2i] = [
	Vector2i(192, 208),  # izquierda
	Vector2i(192, 224),  # abajo
	Vector2i(192, 192),  # arriba
	Vector2i(192, 240),  # derecha
	Vector2i(128, 128),  # espacio
]

static var _atlases := {}   # light (bool) -> Texture2D, o null si no existe
static var _cache := {}     # "lane:variant:light" -> AtlasTexture


static func available() -> bool:
	return _atlas(false) != null and _atlas(true) != null


## Textura de la tecla de un carril, o null si no hay atlas.
## `light` elige el juego de teclas claras en vez de las oscuras.
static func texture(lane: int, variant: Variant, light: bool = false) -> Texture2D:
	var key := "%d:%d:%s" % [lane, variant, light]
	if _cache.has(key):
		return _cache[key]
	var atlas := _atlas(light)
	if atlas == null:
		return null
	var cell := LANE_CELLS[lane]
	var tex := AtlasTexture.new()
	tex.atlas = atlas
	tex.region = Rect2(cell.x + variant * CELL, cell.y, CELL, CELL)
	_cache[key] = tex
	return tex


## Icono listo para meter en la UI. Sin atlas, devuelve un Label de reserva.
static func make_icon(lane: int, px: int, variant: Variant = Variant.NORMAL,
		light: bool = true) -> Control:
	var tex := texture(lane, variant, light)
	if tex == null:
		var label := Label.new()
		label.text = Lanes.ARROWS[lane]
		label.custom_minimum_size = Vector2(px, px)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(px * 0.6))
		label.add_theme_color_override("font_color", Lanes.COLORS[lane])
		return label
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = Vector2(px, px)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Pixel art: sin esto se escala con filtro lineal y queda borroso.
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect


static func _atlas(light: bool) -> Texture2D:
	if not _atlases.has(light):
		var path := LIGHT_PATH if light else DARK_PATH
		_atlases[light] = load(path) if ResourceLoader.exists(path) else null
	return _atlases[light]
