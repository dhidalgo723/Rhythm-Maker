extends Node

## Verifica el tema de pixel art y la navegacion por teclado de los menus.
##   1. el tema se construye con las piezas del atlas
##   2. W/A/S/D y las flechas estan en las acciones ui_*
##   3. W/A/S/D y las flechas mueven el foco de verdad
##   4. cada pantalla de menu arranca con algo seleccionado
##   5. en partida, grabacion y calibracion NADA tiene el foco, y WASD sigue
##      llegando a los carriles despues de pausar y reanudar
## Correr: godot --headless --path . res://tests/smoke_gui.tscn

var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioServer.set_bus_mute(0, true)
	await get_tree().process_frame

	_test_theme()
	_test_actions()
	await _test_navigation()
	await _test_initial_focus()
	await _test_no_focus_while_playing()
	await _test_no_focus_while_recording()
	await _test_no_focus_while_calibrating()

	get_tree().paused = false
	print("SMOKE TEST %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("  FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


func _wait(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


## Evento de tecla como los que manda el sistema: con codigo logico y fisico.
func _key(code: int, pressed: bool = true) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	return ev


func _tap(code: int) -> void:
	Input.parse_input_event(_key(code, true))
	Input.parse_input_event(_key(code, false))
	await _wait(2)


# --- 1 ---
func _test_theme() -> void:
	_check(GuiTheme.available(), "no se encuentra el atlas GUI/gui retro.png")
	var screen := GuiTheme.piece(GuiTheme.PANEL)
	_check(screen != null and screen.get_size() == Vector2(93, 78) * GuiTheme.SCALE,
		"la pantalla de casete deberia medir 186x156 una vez escalada")

	var theme := ThemeDB.get_default_theme()
	_check(theme.get_stylebox("normal", "Button") is StyleBoxTexture,
		"los botones deberian usar las texturas del atlas")
	_check(theme.is_type_variation("BigButton", "Button"), "falta la variacion BigButton")
	_check(theme.get_stylebox("panel", "PanelContainer") is StyleBoxTexture,
		"los paneles deberian usar el marco del atlas")
	print("[tema] piezas del atlas cargadas y aplicadas al tema por defecto")


# --- 2 ---
func _test_actions() -> void:
	var expected := {
		"ui_up": [KEY_W, KEY_UP], "ui_down": [KEY_S, KEY_DOWN],
		"ui_left": [KEY_A, KEY_LEFT], "ui_right": [KEY_D, KEY_RIGHT],
	}
	for action in expected:
		for code in expected[action]:
			_check(InputMap.event_is_action(_key(code), action),
				"%s deberia activarse con %s" % [action, OS.get_keycode_string(code)])
	print("[acciones] W/A/S/D y flechas en ui_up/down/left/right")


# --- 3 ---
func _test_navigation() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var col: Array[Button] = []
	for i in 3:
		var b := Button.new()
		b.text = "fila %d" % i
		box.add_child(b)
		col.append(b)
	var row := HBoxContainer.new()
	box.add_child(row)
	var left := Button.new()
	left.text = "izq"
	row.add_child(left)
	var right := Button.new()
	right.text = "der"
	row.add_child(right)
	await _wait()

	col[0].grab_focus()
	await _tap(KEY_S)
	_check(_focus() == col[1], "S deberia bajar a la fila 1")
	await _tap(KEY_DOWN)
	_check(_focus() == col[2], "la flecha abajo deberia bajar a la fila 2")
	await _tap(KEY_W)
	_check(_focus() == col[1], "W deberia subir a la fila 1")
	await _tap(KEY_UP)
	_check(_focus() == col[0], "la flecha arriba deberia subir a la fila 0")

	left.grab_focus()
	await _tap(KEY_D)
	_check(_focus() == right, "D deberia ir a la derecha")
	await _tap(KEY_A)
	_check(_focus() == left, "A deberia ir a la izquierda")
	await _tap(KEY_RIGHT)
	_check(_focus() == right, "la flecha derecha deberia ir a la derecha")
	await _tap(KEY_LEFT)
	_check(_focus() == left, "la flecha izquierda deberia ir a la izquierda")

	box.queue_free()
	await _wait()
	print("[navegacion] WASD y flechas mueven el foco en las cuatro direcciones")


# --- 4 ---
func _test_initial_focus() -> void:
	var library := Library.list_songs()
	for path in ["main_menu", "edit_menu", "song_select", "settings_scene", "calibration_scene"]:
		var scene: Node = load("res://scenes/%s.tscn" % path).instantiate()
		add_child(scene)
		await _wait(4)
		var f := _focus()
		_check(f != null and scene.is_ancestor_of(f),
			"%s deberia empezar con un control seleccionado" % path)
		# En la lista de canciones, lo primero debe ser una cancion (si hay).
		if path == "song_select" and not library.is_empty() and f is Button:
			_check((f as Button).text.contains(library[0].title()),
				"la lista deberia empezar en la primera cancion, no en '%s'" % (f as Button).text)
		scene.queue_free()
		await _wait()
	print("[foco inicial] todas las pantallas de menu empiezan con algo seleccionado")


# --- 5 ---
func _tone_entry() -> SongEntry:
	var e := SongEntry.new()
	e.slug = "tono"
	e.dir = ProjectSettings.globalize_path("res://tests")
	e.chart = Chart.new()
	e.chart.title = "tono"
	e.chart.song_path = "test_tone.wav"
	# Notas lejanas: nada debe marcarse como errada durante el test.
	e.chart.add_note(60000, 2)
	return e


func _test_no_focus_while_playing() -> void:
	Session.selected_song = _tone_entry()
	var scene: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(PlayScene_COUNTDOWN + 0.4).timeout
	_check(scene._started, "la partida deberia haber empezado tras la cuenta atras")
	_check(_focus() == null, "durante la partida nada deberia tener el foco")

	scene._set_paused(true)
	await _wait()
	_check(_focus() == scene._resume_btn, "al pausar, el foco deberia ir a Reanudar")
	await _tap(KEY_S)
	_check(_focus() != scene._resume_btn, "en pausa, S deberia moverse por el menu")

	scene._set_paused(false)
	await _wait()
	_check(_focus() == null, "al reanudar se deberia soltar el foco")

	# Y lo que importa: W vuelve a ser un carril, no navegacion.
	var lanes: Array[int] = []
	scene._pm.lane_pressed.connect(func(l: int) -> void: lanes.append(l))
	Input.parse_input_event(_key(Settings.binding(Settings.SLOT_SECONDARY, 2)))
	await _wait(2)
	_check(lanes == [2], "tras reanudar, W deberia llegar al carril arriba (llego %s)" % str(lanes))

	scene._pm.stop()
	scene.queue_free()
	get_tree().paused = false
	await _wait()
	print("[partida] sin foco al jugar; pausa navegable; WASD vuelve a los carriles")


const PlayScene_COUNTDOWN := 3.0


func _test_no_focus_while_recording() -> void:
	Session.recording_title = "gui"
	Session.set_audio(ProjectSettings.globalize_path("res://tests/test_tone.wav"))
	var scene: Node = load("res://scenes/recording_scene.tscn").instantiate()
	add_child(scene)
	await _wait(5)
	_check(_focus() == null, "durante la grabacion nada deberia tener el foco")
	scene.queue_free()
	await _wait()
	print("[grabacion] sin foco mientras se graba")


func _test_no_focus_while_calibrating() -> void:
	var scene: Node = load("res://scenes/calibration_scene.tscn").instantiate()
	add_child(scene)
	await _wait(4)
	_check(_focus() != null, "la calibracion deberia empezar con EMPEZAR seleccionado")
	scene._on_start()
	await _wait(2)
	_check(_focus() == null, "midiendo, ESPACIO no puede ir a un boton: nada con foco")
	scene._cal.stop()
	scene.queue_free()
	await _wait()
	print("[calibracion] sin foco mientras se mide")
