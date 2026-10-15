class_name Lanes
extends RefCounted

const COUNT := 5

## Id del carril, que es lo que se guarda en los charts:
##   0=izquierda, 1=abajo, 2=arriba, 3=derecha, 4=espacio
## El espacio es el 4 aunque se dibuje en el centro: asi los charts grabados
## cuando solo habia cuatro carriles siguen significando lo mismo.
const ACTIONS: Array[String] = ["lane_0", "lane_1", "lane_2", "lane_3", "lane_4"]
## Solo para cuando no hay iconos (ver KeyIcons): texto de reserva.
const ARROWS: Array[String] = ["<", "v", "^", ">", "_"]
const NAMES: Array[String] = ["Izquierda", "Abajo", "Arriba", "Derecha", "Espacio"]

const SPACE := 4

## Orden en pantalla, de izquierda a derecha. Todo lo que dibuje carriles debe
## recorrer esto y no 0..COUNT, o el espacio acabaria a la derecha del todo.
const DISPLAY_ORDER: Array[int] = [0, 1, SPACE, 2, 3]

## OS.get_keycode_string() devuelve los nombres en ingles. Con el juego en
## espanol se traducen las teclas con nombre propio: las letras y los numeros
## ya se llaman igual.
const KEY_NAMES_ES := {
	"Left": "Izq", "Right": "Der", "Up": "Arriba", "Down": "Abajo",
	"Space": "Espacio", "Enter": "Intro", "Shift": "Mayús", "Ctrl": "Ctrl",
	"Alt": "Alt", "Tab": "Tab", "Backspace": "Retroceso", "Delete": "Supr",
	"Insert": "Insert", "Home": "Inicio", "End": "Fin",
	"PageUp": "RePág", "PageDown": "AvPág",
}
const COLORS: Array[Color] = [
	Color("c24b99"),  # izq   - magenta
	Color("00ffff"),  # abajo - cyan
	Color("12fa05"),  # arriba- verde
	Color("f9393f"),  # der   - rojo
	Color("ffd23f"),  # espacio - amarillo
]


## Nombre del carril en el idioma actual.
static func lane_name(lane: int) -> String:
	return Lang.t(NAMES[lane])


## Posicion en pantalla (0 = la mas a la izquierda) de un carril.
static func display_index(lane: int) -> int:
	return DISPLAY_ORDER.find(lane)


## Devuelve el lane pulsado por este evento, o -1.
## Ignora echo (auto-repeat) para no generar notas fantasma.
static func lane_pressed(event: InputEvent) -> int:
	if event is InputEventKey and (event as InputEventKey).echo:
		return -1
	for i in COUNT:
		if event.is_action_pressed(ACTIONS[i]):
			return i
	return -1


static func lane_released(event: InputEvent) -> int:
	for i in COUNT:
		if event.is_action_released(ACTIONS[i]):
			return i
	return -1


## Nombre visible de la tecla de un lane. Por defecto, la principal.
static func key_label(lane: int, slot: int = Settings.SLOT_PRIMARY) -> String:
	return key_name(Settings.binding(slot, lane))


## Las dos teclas de un lane juntas: "Izq / A", o solo "Izq" si no hay secundaria.
static func key_label_pair(lane: int) -> String:
	var primary := key_label(lane, Settings.SLOT_PRIMARY)
	if Settings.binding(Settings.SLOT_SECONDARY, lane) == Settings.NO_KEY:
		return primary
	return "%s / %s" % [primary, key_label(lane, Settings.SLOT_SECONDARY)]


## Traduce un physical keycode al nombre que ese sitio del teclado tiene en la
## distribucion del usuario: la posicion de "W" en QWERTY se llama "Z" en AZERTY
## y hay que ensenarle "Z", no "W".
##
## El display server headless no sabe de distribuciones y aborta la llamada con
## un error, asi que ahi se usa el nombre del keycode fisico tal cual.
static func key_name(physical_keycode: int) -> String:
	if physical_keycode == 0:
		return "-"
	var label := ""
	if DisplayServer.get_name() != "headless":
		var local := DisplayServer.keyboard_get_keycode_from_physical(physical_keycode)
		if local != 0:
			label = OS.get_keycode_string(local)
	if label == "":
		label = OS.get_keycode_string(physical_keycode)
	if label == "":
		return "?"
	if TranslationServer.get_locale().begins_with("es"):
		return KEY_NAMES_ES.get(label, label)
	return label


## Resumen tipo "Izq Abajo Arriba Der  o  A S W D" para las ayudas en pantalla.
static func keys_hint() -> String:
	var hint := _slot_hint(Settings.SLOT_PRIMARY)
	if not Settings.slot_is_empty(Settings.SLOT_SECONDARY):
		hint += "  %s  " % Lang.t("o") + _slot_hint(Settings.SLOT_SECONDARY)
	return hint


static func _slot_hint(slot: int) -> String:
	var parts: Array[String] = []
	for i in DISPLAY_ORDER:
		var keycode := Settings.binding(slot, i)
		parts.append(key_name(keycode) if keycode != Settings.NO_KEY else "-")
	return " ".join(parts)
