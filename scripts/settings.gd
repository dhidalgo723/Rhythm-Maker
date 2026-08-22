extends Node

## Autoload: Settings. Preferencias persistentes del usuario.

const CONFIG_PATH := "user://settings.cfg"

## Offset de calibracion, en ms.
## Positivo = los inputs del usuario llegan TARDE respecto al audio que oye.
## Se resta al timestamp del input, tanto al grabar como al juzgar hits.
var offset_ms := 0

## Cuanto tarda una nota en cruzar la pantalla, en ms (scroll speed).
var travel_time_ms := 1200

var last_audio_dir := "user://"

# --- Teclas ---
#
# Se guardan como PHYSICAL keycodes: identifican la POSICION de la tecla, no la
# letra impresa. Asi WASD sigue cayendo bajo los mismos dedos en un teclado
# AZERTY, donde esa posicion se llama ZQSD. Para mostrarlas por pantalla se
# traduce al nombre segun la distribucion del usuario (ver Lanes.key_name).

## Indice = lane: 0=izq, 1=abajo, 2=arriba, 3=derecha
const DEFAULT_KEYS: Array[int] = [KEY_LEFT, KEY_DOWN, KEY_UP, KEY_RIGHT]

const PRESETS := {
	"Flechas": DEFAULT_KEYS,
	"WASD": [KEY_A, KEY_S, KEY_W, KEY_D],
	"DFJK": [KEY_D, KEY_F, KEY_J, KEY_K],
}

## Teclas que no se pueden asignar: romperian la navegacion de menus.
const RESERVED: Array[int] = [KEY_ESCAPE]

var key_bindings: Array[int] = DEFAULT_KEYS.duplicate()

signal bindings_changed()


func _ready() -> void:
	load_settings()
	apply_bindings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	offset_ms = int(cfg.get_value("timing", "offset_ms", offset_ms))
	travel_time_ms = int(cfg.get_value("gameplay", "travel_time_ms", travel_time_ms))
	last_audio_dir = str(cfg.get_value("paths", "last_audio_dir", last_audio_dir))
	key_bindings = _sanitize(cfg.get_value("input", "key_bindings", DEFAULT_KEYS))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("timing", "offset_ms", offset_ms)
	cfg.set_value("gameplay", "travel_time_ms", travel_time_ms)
	cfg.set_value("paths", "last_audio_dir", last_audio_dir)
	cfg.set_value("input", "key_bindings", key_bindings)
	cfg.save(CONFIG_PATH)


## Vuelca key_bindings al InputMap. El resto del juego solo usa las acciones
## lane_N, asi que con esto basta para que grabacion y juego usen las teclas
## nuevas sin tocar nada mas.
func apply_bindings() -> void:
	for lane in key_bindings.size():
		var action: String = Lanes.ACTIONS[lane]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = key_bindings[lane]
		InputMap.action_add_event(action, ev)
	bindings_changed.emit()


## Asigna una tecla a un lane. Si ya la tenia otro lane, se intercambian, que
## es lo que espera cualquiera que este reasignando teclas de una en una.
## Devuelve false si la tecla esta reservada.
func set_binding(lane: int, physical_keycode: int) -> bool:
	if physical_keycode in RESERVED or physical_keycode == 0:
		return false
	var previous: int = key_bindings[lane]
	var other := key_bindings.find(physical_keycode)
	if other != -1 and other != lane:
		key_bindings[other] = previous
	key_bindings[lane] = physical_keycode
	apply_bindings()
	save_settings()
	return true


func apply_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	key_bindings = _sanitize(PRESETS[name])
	apply_bindings()
	save_settings()


## Nombre del preset que coincide con las teclas actuales, o "" si es a medida.
func current_preset() -> String:
	for name in PRESETS:
		if key_bindings == _sanitize(PRESETS[name]):
			return name
	return ""


## Un binding valido tiene exactamente COUNT teclas, todas distintas y no nulas.
## Si lo guardado esta corrupto se vuelve a los valores por defecto en vez de
## arrancar con acciones sin tecla y el juego mudo a los inputs.
static func _sanitize(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if raw is Array and (raw as Array).size() == Lanes.COUNT:
		var seen := {}
		for v in raw as Array:
			var k := int(v)
			if k == 0 or seen.has(k):
				return DEFAULT_KEYS.duplicate()
			seen[k] = true
			out.append(k)
		return out
	return DEFAULT_KEYS.duplicate()
