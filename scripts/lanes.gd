class_name Lanes
extends RefCounted

const COUNT := 4

## Indice = lane. 0=izq, 1=abajo, 2=arriba, 3=derecha
const ACTIONS: Array[String] = ["lane_0", "lane_1", "lane_2", "lane_3"]
const ARROWS: Array[String] = ["<", "v", "^", ">"]
const NAMES: Array[String] = ["Izquierda", "Abajo", "Arriba", "Derecha"]

## OS.get_keycode_string() devuelve los nombres en ingles; el resto de la UI
## esta en espanol. Solo se traducen las teclas con nombre propio: las letras
## y los numeros ya se llaman igual.
const KEY_NAMES_ES := {
	"Left": "Izq", "Right": "Der", "Up": "Arriba", "Down": "Abajo",
	"Space": "Espacio", "Enter": "Intro", "Shift": "Mayus", "Ctrl": "Ctrl",
	"Alt": "Alt", "Tab": "Tab", "Backspace": "Retroceso", "Delete": "Supr",
	"Insert": "Insert", "Home": "Inicio", "End": "Fin",
	"PageUp": "RePag", "PageDown": "AvPag",
}
const COLORS: Array[Color] = [
	Color("c24b99"),  # izq   - magenta
	Color("00ffff"),  # abajo - cyan
	Color("12fa05"),  # arriba- verde
	Color("f9393f"),  # der   - rojo
]


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


## Nombre visible de la tecla asignada a un lane.
static func key_label(lane: int) -> String:
	return key_name(Settings.key_bindings[lane])


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
	return KEY_NAMES_ES.get(label, label)


## Resumen tipo "A S W D" para los textos de ayuda en pantalla.
static func keys_hint() -> String:
	var parts: Array[String] = []
	for i in COUNT:
		parts.append(key_label(i))
	return " ".join(parts)
