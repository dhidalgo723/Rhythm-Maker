extends Node

## Verifica que reasignar teclas afecta de verdad al input del juego, con las
## dos ranuras por carril (principal y secundaria).
## Correr: godot --headless --path . res://tests/smoke_bindings.tscn

const P := 0   # Settings.SLOT_PRIMARY
const S := 1   # Settings.SLOT_SECONDARY

var _failed := false


func _ready() -> void:
	var original := Settings.key_bindings.duplicate()
	var original_alt := Settings.key_bindings_alt.duplicate()

	_test_defaults()
	await _test_both_slots_work()
	_test_presets_per_slot()
	_test_swap_on_duplicate()
	_test_primary_never_empties()
	_test_clear_secondary()
	_test_reserved_keys()
	_test_persistence()
	_test_corrupt_config()

	# Dejar las preferencias del usuario como estaban.
	Settings.key_bindings = original
	Settings.key_bindings_alt = original_alt
	Settings.apply_bindings()
	Settings.save_settings()

	print("SMOKE TEST %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("  FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


## Todas las teclas que el InputMap tiene asociadas a un carril.
func _bound_keys(lane: int) -> Array[int]:
	var out: Array[int] = []
	for ev in InputMap.action_get_events(Lanes.ACTIONS[lane]):
		out.append((ev as InputEventKey).physical_keycode)
	return out


func _lane_for(physical: int) -> int:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = true
	return Lanes.lane_pressed(ev)


func _reset() -> void:
	Settings.apply_preset(P, "Flechas")
	Settings.apply_preset(S, "WASD")


func _test_defaults() -> void:
	_reset()
	_check(Settings.key_bindings == Settings.DEFAULT_KEYS, "la principal deberia ser Flechas")
	_check(Settings.key_bindings_alt == Settings.DEFAULT_KEYS_ALT, "la secundaria deberia ser WASD")
	_check(_bound_keys(2) == [KEY_UP, KEY_W], "arriba deberia tener flecha y W: %s" % str(_bound_keys(2)))
	print("[defaults] %s" % Lanes.keys_hint())


## Lo que de verdad importa: que las DOS teclas de un carril lo activen.
func _test_both_slots_work() -> void:
	_reset()
	await get_tree().process_frame
	_check(_lane_for(KEY_UP) == 2, "la flecha arriba deberia activar el carril arriba")
	_check(_lane_for(KEY_W) == 2, "W deberia activar el mismo carril arriba")
	_check(_lane_for(KEY_A) == 0, "A deberia activar el carril izquierda")
	_check(_lane_for(KEY_J) == -1, "J no deberia hacer nada")

	Settings.apply_preset(S, "")
	await get_tree().process_frame
	_check(_lane_for(KEY_UP) == 2, "sin secundaria, la flecha debe seguir funcionando")
	_check(_lane_for(KEY_W) == -1, "sin secundaria, W ya no deberia hacer nada")
	print("[input] las dos ranuras activan el carril, y quitarlas surte efecto")


func _test_presets_per_slot() -> void:
	_reset()
	_check(Settings.apply_preset(S, "DFJK") == "", "DFJK deberia poder ser la secundaria")
	_check(Settings.key_bindings_alt == [KEY_D, KEY_F, KEY_J, KEY_K], "secundaria mal aplicada")
	_check(Settings.current_preset(P) == "Flechas", "no reconoce Flechas en la principal")
	_check(Settings.current_preset(S) == "DFJK", "no reconoce DFJK en la secundaria")

	# Poner en la principal un preset que ya usa la secundaria: la secundaria cede.
	_check(Settings.apply_preset(P, "DFJK") == "", "la principal deberia poder quedarse DFJK")
	_check(Settings.slot_is_empty(S), "la secundaria deberia haber cedido sus teclas")
	print("[presets] por ranura, y la secundaria cede ante la principal")


func _test_swap_on_duplicate() -> void:
	_reset()
	# Dar a "izquierda" la flecha derecha, que ya tenia otro carril.
	_check(Settings.set_binding(P, 0, KEY_RIGHT) == "", "deberia dejar reasignar")
	_check(Settings.binding(P, 0) == KEY_RIGHT, "izquierda deberia quedarse la flecha derecha")
	_check(Settings.binding(P, 3) == KEY_LEFT, "derecha deberia recibir la flecha izquierda")

	# Tambien debe intercambiar entre ranuras distintas.
	_reset()
	_check(Settings.set_binding(S, 0, KEY_LEFT) == "", "deberia intercambiar entre ranuras")
	_check(Settings.binding(S, 0) == KEY_LEFT, "la secundaria de izquierda deberia ser la flecha")
	_check(Settings.binding(P, 0) == KEY_A, "la principal de izquierda deberia recibir la A")
	_check_all_unique()
	print("[swap] intercambio dentro y entre ranuras")


## Nunca puede quedar un carril sin tecla principal, o deja de responder.
func _test_primary_never_empties() -> void:
	_reset()
	Settings.clear_binding(S, 2)                     # arriba se queda sin secundaria
	var err := Settings.set_binding(S, 2, KEY_UP)    # y ahora le pedimos su propia principal
	_check(err != "", "no deberia poder vaciar la principal de un carril")
	_check(Settings.binding(P, 2) == KEY_UP, "la principal de arriba sigue siendo la flecha")

	_check(Settings.clear_binding(P, 0) != "", "no deberia poder quitarse una principal")
	_check(Settings.binding(P, 0) != Settings.NO_KEY, "izquierda se quedo sin principal")

	_check(Settings.apply_preset(P, "") != "", "la principal no puede quedarse sin preset")
	print("[invariante] la tecla principal nunca se queda vacia")


func _test_clear_secondary() -> void:
	_reset()
	_check(Settings.clear_binding(S, 1) == "", "deberia poder quitarse una secundaria")
	_check(Settings.binding(S, 1) == Settings.NO_KEY, "la secundaria sigue puesta")
	_check(_bound_keys(1) == [KEY_DOWN], "el carril deberia quedarse con una sola tecla")
	_check(not Settings.slot_is_empty(S), "las otras secundarias siguen ahi")
	print("[limpiar] se puede quitar una secundaria suelta")


func _test_reserved_keys() -> void:
	_reset()
	var before := Settings.key_bindings.duplicate()
	_check(Settings.set_binding(P, 0, KEY_ESCAPE) != "", "Esc no deberia poder asignarse")
	_check(Settings.key_bindings == before, "un binding rechazado no debe cambiar nada")
	print("[reservadas] Esc rechazada")


func _test_persistence() -> void:
	Settings.apply_preset(P, "DFJK")
	Settings.apply_preset(S, "Flechas")
	Settings.key_bindings = [0, 0, 0, 0]        # ensuciar la memoria
	Settings.key_bindings_alt = [0, 0, 0, 0]
	Settings.load_settings()
	_check(Settings.key_bindings == [KEY_D, KEY_F, KEY_J, KEY_K],
		"la principal no sobrevivio al disco: %s" % str(Settings.key_bindings))
	_check(Settings.key_bindings_alt == Settings.DEFAULT_KEYS,
		"la secundaria no sobrevivio al disco: %s" % str(Settings.key_bindings_alt))
	print("[persistencia] las dos ranuras releidas del disco")


## Un settings.cfg corrupto no debe dejar el juego sin teclas.
func _test_corrupt_config() -> void:
	for bad in [[KEY_A, KEY_A, KEY_W, KEY_D], [KEY_A, KEY_S], [], "basura"]:
		_check(Settings._sanitize_slot(bad, false).is_empty(),
			"entrada corrupta %s deberia rechazarse" % str(bad))
	# La secundaria si admite huecos; la principal no.
	_check(Settings._sanitize_slot([0, 0, 0, 0], true) == [0, 0, 0, 0],
		"la secundaria deberia poder estar vacia")
	_check(Settings._sanitize_slot([0, 0, 0, 0], false).is_empty(),
		"la principal no puede estar vacia")
	print("[corrupcion] entradas invalidas rechazadas")


func _check_all_unique() -> void:
	var seen := {}
	for slot in Settings.SLOT_COUNT:
		for k in Settings.slot_keys(slot):
			if k == Settings.NO_KEY:
				continue
			_check(not seen.has(k), "la tecla %s esta asignada dos veces" % Lanes.key_name(k))
			seen[k] = true
