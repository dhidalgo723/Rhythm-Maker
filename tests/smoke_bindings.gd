extends Node

## Verifica que reasignar teclas afecta de verdad al input del juego, con las
## dos ranuras por carril (principal y secundaria) y el carril espacio.
## Correr: godot --headless --path . res://tests/smoke_bindings.tscn

const P := 0   # Settings.SLOT_PRIMARY
const S := 1   # Settings.SLOT_SECONDARY
const N := 0   # Settings.NO_KEY

var _failed := false


func _ready() -> void:
	# Se guarda el settings.cfg tal cual para devolverlo al final: los tests
	# escriben en el y no deben pisar la configuracion real del jugador.
	var backup := _read_config()

	_test_defaults()
	await _test_both_slots_work()
	await _test_space_lane()
	_test_presets_per_slot()
	_test_presets_leave_space_alone()
	_test_swap_on_duplicate()
	_test_primary_never_empties()
	_test_clear_secondary()
	_test_reserved_keys()
	_test_persistence()
	_test_corrupt_config()
	_test_migration_from_v1()

	_restore_config(backup)

	print("SMOKE TEST %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("  FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


func _read_config() -> String:
	if not FileAccess.file_exists(Settings.CONFIG_PATH):
		return ""
	return FileAccess.get_file_as_string(Settings.CONFIG_PATH)


func _restore_config(text: String) -> void:
	if text == "":
		DirAccess.remove_absolute(Settings.CONFIG_PATH)
	else:
		var f := FileAccess.open(Settings.CONFIG_PATH, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	Settings.load_settings()
	Settings.apply_bindings()


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
	Settings.key_bindings = Settings.DEFAULT_KEYS.duplicate()
	Settings.key_bindings_alt = Settings.DEFAULT_KEYS_ALT.duplicate()
	Settings.apply_bindings()


func _test_defaults() -> void:
	_reset()
	_check(Settings.key_bindings == [KEY_LEFT, KEY_DOWN, KEY_UP, KEY_RIGHT, KEY_SPACE],
		"la principal deberia ser flechas + espacio")
	_check(Settings.key_bindings_alt == [KEY_A, KEY_S, KEY_W, KEY_D, N],
		"la secundaria deberia ser WASD, sin tecla para el espacio")
	_check(_bound_keys(2) == [KEY_UP, KEY_W], "arriba deberia tener flecha y W: %s" % str(_bound_keys(2)))
	_check(_bound_keys(Lanes.SPACE) == [KEY_SPACE], "el espacio deberia tener solo la barra")
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


func _test_space_lane() -> void:
	_reset()
	await get_tree().process_frame
	_check(_lane_for(KEY_SPACE) == Lanes.SPACE, "la barra espaciadora deberia activar su carril")
	# Se dibuja en el centro aunque su id sea el 4.
	_check(Lanes.display_index(Lanes.SPACE) == 2, "el espacio deberia ir en el centro")
	_check(Lanes.DISPLAY_ORDER.size() == Lanes.COUNT, "el orden de pantalla no cubre todos los carriles")

	# Se puede reasignar como cualquier otro.
	_check(Settings.set_binding(P, Lanes.SPACE, KEY_B) == "", "deberia poder cambiarse la tecla del espacio")
	await get_tree().process_frame
	_check(_lane_for(KEY_B) == Lanes.SPACE, "B deberia activar ahora el carril espacio")
	_check(_lane_for(KEY_SPACE) == -1, "la barra ya no deberia hacer nada")
	print("[espacio] carril central, reasignable")


func _test_presets_per_slot() -> void:
	_reset()
	_check(Settings.apply_preset(S, "DFJK") == "", "DFJK deberia poder ser la secundaria")
	_check(Settings.key_bindings_alt == [KEY_D, KEY_F, KEY_J, KEY_K, N], "secundaria mal aplicada")
	_check(Settings.current_preset(P) == "Flechas", "no reconoce Flechas en la principal")
	_check(Settings.current_preset(S) == "DFJK", "no reconoce DFJK en la secundaria")

	# Poner en la principal un preset que ya usa la secundaria: la secundaria cede.
	_check(Settings.apply_preset(P, "DFJK") == "", "la principal deberia poder quedarse DFJK")
	_check(Settings.slot_is_empty(S), "la secundaria deberia haber cedido sus teclas")
	print("[presets] por ranura, y la secundaria cede ante la principal")


## Un preset es sobre las flechas: elegirlo no debe cambiar la tecla del espacio.
func _test_presets_leave_space_alone() -> void:
	_reset()
	Settings.apply_preset(P, "WASD")
	_check(Settings.binding(P, Lanes.SPACE) == KEY_SPACE, "elegir WASD cambio la tecla del espacio")
	_check(Settings.current_preset(P) == "WASD", "con el espacio aparte deberia seguir reconociendo WASD")

	# Si el espacio de la secundaria usa una letra que el preset reparte, la suelta.
	_reset()
	Settings.set_binding(S, Lanes.SPACE, KEY_J)
	_check(Settings.apply_preset(S, "DFJK") == "", "DFJK en la secundaria deberia aplicarse")
	_check(Settings.binding(S, Lanes.SPACE) == N, "el espacio deberia soltar la J")
	_check(Settings.binding(S, 2) == KEY_J, "arriba deberia quedarse la J")

	# En la principal el espacio no puede quedarse vacio: se rechaza el preset.
	_reset()
	Settings.apply_preset(S, "")
	Settings.set_binding(P, Lanes.SPACE, KEY_K)
	var err := Settings.apply_preset(P, "DFJK")
	_check(err != "", "un preset que vaciaria el espacio principal deberia rechazarse")
	_check(Settings.binding(P, Lanes.SPACE) == KEY_K, "el rechazo no deberia cambiar nada")
	_check_all_unique()
	print("[presets] el carril espacio queda fuera de los presets")


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
	_check(Settings.binding(P, 0) != N, "izquierda se quedo sin principal")

	_check(Settings.apply_preset(P, "") != "", "la principal no puede quedarse sin preset")
	print("[invariante] la tecla principal nunca se queda vacia")


func _test_clear_secondary() -> void:
	_reset()
	_check(Settings.clear_binding(S, 1) == "", "deberia poder quitarse una secundaria")
	_check(Settings.binding(S, 1) == N, "la secundaria sigue puesta")
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
	_reset()
	Settings.apply_preset(P, "DFJK")
	Settings.apply_preset(S, "Flechas")
	Settings.key_bindings = [N, N, N, N, N]        # ensuciar la memoria
	Settings.key_bindings_alt = [N, N, N, N, N]
	Settings.load_settings()
	_check(Settings.key_bindings == [KEY_D, KEY_F, KEY_J, KEY_K, KEY_SPACE],
		"la principal no sobrevivio al disco: %s" % str(Settings.key_bindings))
	_check(Settings.key_bindings_alt == [KEY_LEFT, KEY_DOWN, KEY_UP, KEY_RIGHT, N],
		"la secundaria no sobrevivio al disco: %s" % str(Settings.key_bindings_alt))
	print("[persistencia] las dos ranuras releidas del disco")


## Un settings.cfg corrupto no debe dejar el juego sin teclas.
func _test_corrupt_config() -> void:
	for bad in [[KEY_A, KEY_A, KEY_W, KEY_D, KEY_SPACE], [KEY_A, KEY_S], [], "basura"]:
		_check(Settings._sanitize_slot(bad, false).is_empty(),
			"entrada corrupta %s deberia rechazarse" % str(bad))
	# La secundaria si admite huecos; la principal no.
	_check(Settings._sanitize_slot([N, N, N, N, N], true) == [N, N, N, N, N],
		"la secundaria deberia poder estar vacia")
	_check(Settings._sanitize_slot([N, N, N, N, N], false).is_empty(),
		"la principal no puede estar vacia")
	print("[corrupcion] entradas invalidas rechazadas")


## Una config guardada antes del carril espacio (4 teclas, sin version) debe
## leerse conservando lo que el jugador tenia, y ganar la barra para el espacio.
func _test_migration_from_v1() -> void:
	_write_v1_config([KEY_D, KEY_F, KEY_J, KEY_K], [KEY_A, KEY_S, KEY_W, KEY_E], 1200)
	Settings.load_settings()
	_check(Settings.key_bindings == [KEY_D, KEY_F, KEY_J, KEY_K, KEY_SPACE],
		"la principal antigua no se migro bien: %s" % str(Settings.key_bindings))
	_check(Settings.key_bindings_alt == [KEY_A, KEY_S, KEY_W, KEY_E, N],
		"la secundaria antigua no se migro bien: %s" % str(Settings.key_bindings_alt))
	_check(Settings.travel_time_ms == Settings.DEFAULT_TRAVEL_MS,
		"la velocidad por defecto antigua deberia subir a la nueva")

	var cfg := ConfigFile.new()
	cfg.load(Settings.CONFIG_PATH)
	_check(int(cfg.get_value("meta", "version", 0)) == Settings.SETTINGS_VERSION,
		"la migracion deberia quedar guardada")

	# Una velocidad que el jugador eligio a mano no se toca.
	_write_v1_config([KEY_LEFT, KEY_DOWN, KEY_UP, KEY_RIGHT], [KEY_A, KEY_S, KEY_W, KEY_D], 900)
	Settings.load_settings()
	_check(Settings.travel_time_ms == 900, "una velocidad elegida a mano no deberia cambiar")

	# Si el jugador ya usaba la barra en una flecha, el espacio no puede robarsela.
	_write_v1_config([KEY_LEFT, KEY_DOWN, KEY_SPACE, KEY_RIGHT], [KEY_A, KEY_S, KEY_W, KEY_D], 1200)
	Settings.load_settings()
	var all_keys := Settings.key_bindings + Settings.key_bindings_alt
	_check(all_keys.count(KEY_SPACE) <= 1, "la barra quedo asignada dos veces tras migrar")
	_check(Settings.binding(P, Lanes.SPACE) != N, "el espacio no puede quedarse sin tecla principal")
	print("[migracion] config de 4 carriles leida sin perder teclas")


func _write_v1_config(primary: Array, secondary: Array, travel: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("timing", "offset_ms", 0)
	cfg.set_value("gameplay", "travel_time_ms", travel)
	cfg.set_value("input", "key_bindings", primary)
	cfg.set_value("input", "key_bindings_alt", secondary)
	cfg.save(Settings.CONFIG_PATH)


func _check_all_unique() -> void:
	var seen := {}
	for slot in Settings.SLOT_COUNT:
		for k in Settings.slot_keys(slot):
			if k == N:
				continue
			_check(not seen.has(k), "la tecla %s esta asignada dos veces" % Lanes.key_name(k))
			seen[k] = true
