class_name RogueArt
extends RefCounted

## Imagenes de los objetos de la tienda.
##
##   - Mejoras de ranura: la imagen de roguelike/upgrades (campo "image" del
##     catalogo). Sin imagen, una tecla de espacio dorada de reserva.
##   - Mejoras de flecha: la tecla de flecha teñida con el color de la mejora.
##   - Consumibles: un frasco del atlas GUI, de un color por consumible.
##
## Cada imagen se recorta a su silueta, se escala para caber en `max_px` y se
## le deja un margen transparente para que el contorno (outline.gdshader) no se
## corte en los bordes.

const UPGRADES_DIR := "res://roguelike/upgrades"
## Fila de frascos del atlas GUI; el campo "potion" del catalogo es la x.
const POTION_Y := 795
const POTION_SIZE := Vector2i(21, 33)
## Margen transparente alrededor, en px: lo que ocupa el contorno.
const OUTLINE_PX := 4
const OUTLINE_SHADER := preload("res://scripts/roguelike/outline.gdshader")
const OUTLINE_IDLE := Color.BLACK
const OUTLINE_SELECTED := Color.WHITE

static var _cache := {}


## Textura lista para el TextureRect con contorno, o null si no hay nada.
static func item_texture(kind: RogueCatalog.ItemKind, id: String, max_px: int) -> Texture2D:
	var key := "%d:%s:%d" % [kind, id, max_px]
	if _cache.has(key):
		return _cache[key]
	var source := _source(kind, id)
	if source.is_empty():
		return null
	var img: Image = source["image"]
	var pixel_art: bool = source["pixel_art"]

	var used := img.get_used_rect()
	if used.size.x == 0 or used.size.y == 0:
		return null
	img = img.get_region(used)
	var longest := maxi(img.get_width(), img.get_height())
	if pixel_art:
		# Escala entera: cada pixel del sprite, un bloque igual.
		var k := maxi(1, max_px / longest)
		img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
	else:
		var k := float(max_px) / longest
		img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)),
			Image.INTERPOLATE_LANCZOS)

	var padded := Image.create_empty(img.get_width() + OUTLINE_PX * 2,
		img.get_height() + OUTLINE_PX * 2, false, Image.FORMAT_RGBA8)
	padded.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(OUTLINE_PX, OUTLINE_PX))
	var tex := ImageTexture.create_from_image(padded)
	_cache[key] = tex
	return tex


## TextureRect con el shader de contorno (cada uno con su propio material, para
## poder resaltar uno sin resaltar todos).
static func make_rect(tex: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	mat.set_shader_parameter("width", float(OUTLINE_PX - 1))
	mat.set_shader_parameter("outline_color", OUTLINE_IDLE)
	rect.material = mat
	return rect


static func set_selected(rect: TextureRect, selected: bool) -> void:
	var mat := rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("outline_color", OUTLINE_SELECTED if selected else OUTLINE_IDLE)


## Hay imagen propia para esta mejora de ranura?
static func has_image(id: String) -> bool:
	var file: String = RogueCatalog.SLOT.get(id, {}).get("image", "")
	return file != "" and ResourceLoader.exists(UPGRADES_DIR.path_join(file))


## {image: Image RGBA8, pixel_art: bool}, o {} si no hay de donde sacarla.
static func _source(kind: RogueCatalog.ItemKind, id: String) -> Dictionary:
	var data := RogueCatalog.item(kind, id)
	match kind:
		RogueCatalog.ItemKind.SLOT:
			if has_image(id):
				var tex: Texture2D = load(UPGRADES_DIR.path_join(data["image"]))
				return {"image": _rgba(tex.get_image()), "pixel_art": false}
			# Sin imagen (de momento Beat Drop): tecla de espacio dorada.
			return _key_image(Lanes.SPACE, Color("ffd23f"))
		RogueCatalog.ItemKind.ARROW:
			return _key_image(2, Color(str(data.get("color", "ffffff"))))
		_:
			if not GuiTheme.available():
				return {}
			var atlas := GuiTheme._atlas_image()
			var region := Rect2i(Vector2i(int(data.get("potion", 159)), POTION_Y), POTION_SIZE)
			return {"image": atlas.get_region(region), "pixel_art": true}


## Tecla del atlas de teclas, teñida.
static func _key_image(lane: int, tint: Color) -> Dictionary:
	var tex := KeyIcons.texture(lane, KeyIcons.Variant.NORMAL, true) as AtlasTexture
	if tex == null:
		return {}
	var img := _rgba(tex.atlas.get_image()).get_region(Rect2i(tex.region))
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	return {"image": img, "pixel_art": true}


static func _rgba(img: Image) -> Image:
	var out := img.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	return out
