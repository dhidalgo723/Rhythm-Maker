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
# Cada carril tiene dos teclas: principal y secundaria, para poder jugar con
# flechas o con WASD sin pasar por Ajustes. La secundaria puede quedar sin
# asignar (0); la principal no, o el carril se quedaria muerto.
#
# Se guardan como PHYSICAL keycodes: identifican la POSICION de la tecla, no la
# letra impresa. Asi WASD sigue cayendo bajo los mismos dedos en un teclado
# AZERTY, donde esa posicion se llama ZQSD. Para mostrarlas por pantalla se
# traduce al nombre segun la distribucion del usuario (ver Lanes.key_name).

const SLOT_PRIMARY := 0
const SLOT_SECONDARY := 1
const SLOT_COUNT := 2
const SLOT_NAMES: Array[String] = ["Principal", "Secundaria"]

## Indice = lane: 0=izq, 1=abajo, 2=arriba, 3=derecha
const DEFAULT_KEYS: Array[int] = [KEY_LEFT, KEY_DOWN, KEY_UP, KEY_RIGHT]
const DEFAULT_KEYS_ALT: Array[int] = [KEY_A, KEY_S, KEY_W, KEY_D]

const NO_KEY := 0

const PRESETS := {
	"Flechas": DEFAULT_KEYS,
	"WASD": DEFAULT_KEYS_ALT,
	"DFJK": [KEY_D, KEY_F, KEY_J, KEY_K],
}

## Teclas que no se pueden asignar: romperian la navegacion de menus.
const RESERVED: Array[int] = [KEY_ESCAPE]

var key_bindings: Array[int] = DEFAULT_KEYS.duplicate()
var key_bindings_alt: Array[int] = DEFAULT_KEYS_ALT.duplicate()

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

	# "key_bindings" es la clave que ya usaban los settings de una sola tecla,
	# asi que una config antigua se lee sola y hereda la secundaria por defecto.
	var primary := _sanitize_slot(cfg.get_value("input", "key_bindings", DEFAULT_KEYS), false)
	if primary.is_empty():
		primary = DEFAULT_KEYS.duplicate()
	var secondary := _sanitize_slot(cfg.get_value("input", "key_bindings_alt", DEFAULT_KEYS_ALT), true)
	if secondary.is_empty():
		secondary = DEFAULT_KEYS_ALT.duplicate()

	# Ante una colision entre slots cede la secundaria: la principal manda.
	for lane in secondary.size():
		if secondary[lane] in primary:
			secondary[lane] = NO_KEY

	key_bindings = primary
	key_bindings_alt = secondary


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("timing", "offset_ms", offset_ms)
	cfg.set_value("gameplay", "travel_time_ms", travel_time_ms)
	cfg.set_value("paths", "last_audio_dir", last_audio_dir)
	cfg.set_value("input", "key_bindings", key_bindings)
	cfg.set_value("input", "key_bindings_alt", key_bindings_alt)
	cfg.save(CONFIG_PATH)


## Las teclas de un slot. Se devuelve el array vivo: para leer, no para trastear.
func slot_keys(slot: int) -> Array[int]:
	return key_bindings_alt if slot == SLOT_SECONDARY else key_bindings


func binding(slot: int, lane: int) -> int:
	return slot_keys(slot)[lane]


## Vuelca las teclas al InputMap. El resto del juego solo usa las acciones
## lane_N, asi que con esto basta para que grabacion y juego usen las teclas
## nuevas sin tocar nada mas.
func apply_bindings() -> void:
	for lane in Lanes.COUNT:
		var action: String = Lanes.ACTIONS[lane]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for slot in SLOT_COUNT:
			var keycode := binding(slot, lane)
			if keycode == NO_KEY:
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	bindings_changed.emit()


## Donde vive una tecla ahora mismo: [slot, lane], o [] si esta libre.
func find_key(physical_keycode: int) -> Array[int]:
	if physical_keycode == NO_KEY:
		return []
	for slot in SLOT_COUNT:
		var lane := slot_keys(slot).find(physical_keycode)
		if lane != -1:
			return [slot, lane]
	return []


## Asigna una tecla. Si ya la tenia otro hueco, se intercambian, que es lo que
## espera cualquiera que este reasignando teclas de una en una.
## Devuelve "" si fue bien, o el motivo del rechazo.
func set_binding(slot: int, lane: int, physical_keycode: int) -> String:
	if physical_keycode == NO_KEY:
		return clear_binding(slot, lane)
	if physical_keycode in RESERVED:
		return "Esa tecla esta reservada, elige otra"

	var previous := binding(slot, lane)
	var owner := find_key(physical_keycode)
	if not owner.is_empty():
		if owner[0] == slot and owner[1] == lane:
			return ""
		# Intercambiar dejaria sin tecla al otro hueco. La secundaria puede
		# quedarse vacia; la principal no, o ese carril deja de responder.
		if owner[0] == SLOT_PRIMARY and previous == NO_KEY:
			return "Esa tecla es la principal de %s, cambiala alli primero" % Lanes.NAMES[owner[1]]
		slot_keys(owner[0])[owner[1]] = previous

	slot_keys(slot)[lane] = physical_keycode
	apply_bindings()
	save_settings()
	return ""


## Quita la tecla de un hueco. Solo la secundaria puede quedarse vacia.
func clear_binding(slot: int, lane: int) -> String:
	if slot == SLOT_PRIMARY:
		return "La tecla principal no se puede quitar"
	key_bindings_alt[lane] = NO_KEY
	apply_bindings()
	save_settings()
	return ""


## Aplica un preset a un slot. "" limpia la secundaria entera.
## Devuelve "" si fue bien, o el motivo del rechazo.
func apply_preset(slot: int, name: String) -> String:
	var candidate: Array[int] = []
	if name == "":
		if slot == SLOT_PRIMARY:
			return "La tecla principal no se puede quitar"
		candidate.resize(Lanes.COUNT)   # todo NO_KEY
	elif PRESETS.has(name):
		candidate = _sanitize_slot(PRESETS[name], false)
	if candidate.is_empty():
		return "Preset desconocido"

	var other := SLOT_SECONDARY if slot == SLOT_PRIMARY else SLOT_PRIMARY
	var other_keys := slot_keys(other)
	if other == SLOT_PRIMARY:
		# La principal no puede vaciarse para dejar sitio a la secundaria.
		for k in candidate:
			if k != NO_KEY and k in other_keys:
				return "Esas teclas ya son las principales, cambialas primero"
	else:
		# La secundaria si cede: se le quitan las teclas que pasan a la principal.
		for k in candidate:
			var collision := other_keys.find(k) if k != NO_KEY else -1
			if collision != -1:
				other_keys[collision] = NO_KEY

	if slot == SLOT_SECONDARY:
		key_bindings_alt = candidate
	else:
		key_bindings = candidate
	apply_bindings()
	save_settings()
	return ""


## Nombre del preset que coincide con las teclas del slot, o "" si es a medida.
func current_preset(slot: int) -> String:
	var keys := slot_keys(slot)
	for name in PRESETS:
		if keys == _sanitize_slot(PRESETS[name], false):
			return name
	return ""


func slot_is_empty(slot: int) -> bool:
	for k in slot_keys(slot):
		if k != NO_KEY:
			return false
	return true


## Un slot valido tiene exactamente COUNT teclas y ninguna repetida. Solo la
## secundaria admite huecos vacios. Devuelve [] si la entrada no sirve, para
## que quien llame decida el fallback en vez de arrancar con carriles mudos.
static func _sanitize_slot(raw: Variant, allow_empty: bool) -> Array[int]:
	var out: Array[int] = []
	if not (raw is Array) or (raw as Array).size() != Lanes.COUNT:
		return out
	var seen := {}
	for v in raw as Array:
		var k := int(v)
		if k == NO_KEY:
			if not allow_empty:
				return []
		elif seen.has(k):
			return []
		else:
			seen[k] = true
		out.append(k)
	return out
