extends Node

## Verifica que reasignar teclas afecta de verdad al input del juego.
## Correr: godot --headless --path . res://tests/smoke_bindings.tscn

var _failed := false


func _ready() -> void:
	var original := Settings.key_bindings.duplicate()

	_test_defaults()
	_test_preset_wasd()
	await _test_input_follows_bindings()
	_test_swap_on_duplicate()
	_test_reserved_keys()
	_test_persistence()
	_test_corrupt_config()

	# Dejar las preferencias del usuario como estaban.
	Settings.key_bindings = original
	Settings.apply_bindings()
	Settings.save_settings()

	print("SMOKE TEST %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("  FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


func _bound_key(lane: int) -> int:
	var events := InputMap.action_get_events(Lanes.ACTIONS[lane])
	if events.is_empty():
		return 0
	return (events[0] as InputEventKey).physical_keycode


func _test_defaults() -> void:
	Settings.apply_preset("Flechas")
	_check(Settings.key_bindings == Settings.DEFAULT_KEYS, "el preset Flechas no restaura los defaults")
	_check(_bound_key(0) == KEY_LEFT, "lane 0 deberia ser flecha izquierda")
	_check(_bound_key(2) == KEY_UP, "lane 2 deberia ser flecha arriba")
	print("[defaults] %s" % Lanes.keys_hint())


func _test_preset_wasd() -> void:
	Settings.apply_preset("WASD")
	# izq=A, abajo=S, arriba=W, der=D
	_check(_bound_key(0) == KEY_A, "izquierda deberia ser A")
	_check(_bound_key(1) == KEY_S, "abajo deberia ser S")
	_check(_bound_key(2) == KEY_W, "arriba deberia ser W")
	_check(_bound_key(3) == KEY_D, "derecha deberia ser D")
	_check(Settings.current_preset() == "WASD", "no reconoce el preset WASD")
	print("[wasd] %s" % Lanes.keys_hint())


## Lo que de verdad importa: que Lanes.lane_pressed responda a la tecla nueva
## y deje de responder a la vieja.
func _test_input_follows_bindings() -> void:
	Settings.apply_preset("WASD")
	await get_tree().process_frame

	_check(_lane_for(KEY_W) == 2, "pulsar W deberia activar el carril arriba")
	_check(_lane_for(KEY_A) == 0, "pulsar A deberia activar el carril izquierda")
	_check(_lane_for(KEY_UP) == -1, "la flecha arriba ya no deberia hacer nada con WASD")

	Settings.apply_preset("Flechas")
	await get_tree().process_frame
	_check(_lane_for(KEY_UP) == 2, "con Flechas, arriba deberia volver a funcionar")
	_check(_lane_for(KEY_W) == -1, "con Flechas, W no deberia hacer nada")
	print("[input] las acciones siguen a los bindings")


func _lane_for(physical: int) -> int:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = true
	return Lanes.lane_pressed(ev)


func _test_swap_on_duplicate() -> void:
	Settings.apply_preset("WASD")
	# Asignar a "izquierda" la D, que ya tenia "derecha": deben intercambiarse.
	Settings.set_binding(0, KEY_D)
	_check(Settings.key_bindings[0] == KEY_D, "izquierda deberia haberse quedado con D")
	_check(Settings.key_bindings[3] == KEY_A, "derecha deberia haber recibido la A de izquierda")
	_check(Settings.key_bindings.size() == 4, "se perdieron bindings al intercambiar")
	var unique := {}
	for k in Settings.key_bindings:
		unique[k] = true
	_check(unique.size() == 4, "hay teclas duplicadas tras el intercambio")
	print("[swap] intercambio correcto: %s" % Lanes.keys_hint())


func _test_reserved_keys() -> void:
	Settings.apply_preset("WASD")
	var before := Settings.key_bindings.duplicate()
	_check(not Settings.set_binding(0, KEY_ESCAPE), "Esc no deberia poder asignarse")
	_check(Settings.key_bindings == before, "un binding rechazado no debe cambiar nada")
	print("[reservadas] Esc rechazada")


func _test_persistence() -> void:
	Settings.apply_preset("DFJK")
	Settings.key_bindings = [0, 0, 0, 0]     # ensuciar la memoria
	Settings.load_settings()
	_check(Settings.key_bindings == [KEY_D, KEY_F, KEY_J, KEY_K],
		"los bindings no sobrevivieron al guardado/carga: %s" % str(Settings.key_bindings))
	print("[persistencia] DFJK releido del disco")


## Un settings.cfg corrupto no debe dejar el juego sin teclas.
func _test_corrupt_config() -> void:
	for bad in [[KEY_A, KEY_A, KEY_W, KEY_D], [KEY_A, KEY_S], [], [0, 0, 0, 0], "basura"]:
		var result := Settings._sanitize(bad)
		_check(result == Settings.DEFAULT_KEYS,
			"entrada corrupta %s deberia caer a los defaults, dio %s" % [str(bad), str(result)])
	print("[corrupcion] entradas invalidas caen a Flechas")
