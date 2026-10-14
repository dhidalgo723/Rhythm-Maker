extends Node

## Capturas de todas las pantallas con el tema de pixel art.
## Correr: godot --path . --disable-vsync res://tests/capture_gui.tscn
## (ver capture.gd para el motivo de --disable-vsync)

const SHOTS := ["main_menu", "edit_menu", "song_select", "settings_scene", "calibration_scene"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioServer.set_bus_mute(0, true)

	for scene_name in SHOTS:
		var scene: Node = load("res://scenes/%s.tscn" % scene_name).instantiate()
		add_child(scene)
		await _wait(0.4)
		# Bajar un par de posiciones con el teclado, para que se vea el cursor
		# en algo que no es el primer control.
		if scene_name == "settings_scene":
			await _tap(KEY_S)
			await _tap(KEY_D)
		await _shoot("gui_" + scene_name)
		scene.queue_free()
		await _wait(0.1)

	await _capture_play()
	get_tree().quit(0)


func _capture_play() -> void:
	var e := SongEntry.new()
	e.slug = "tono"
	e.dir = ProjectSettings.globalize_path("res://tests")
	e.chart = Chart.new()
	e.chart.title = "Tono de prueba"
	e.chart.song_path = "test_tone.wav"
	e.chart.add_note(60000, 0)
	Session.selected_song = e

	var scene: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(scene)
	await _wait(3.4)
	scene._set_paused(true)
	await _tap(KEY_S)
	await _shoot("gui_pausa")
	scene._set_paused(false)

	# Resultados con numeros de ejemplo.
	scene._pm.counts[Judgement.Kind.PERFECT] = 120
	scene._pm.counts[Judgement.Kind.GOOD] = 31
	scene._pm.counts[Judgement.Kind.NORMAL] = 9
	scene._pm.counts[Judgement.Kind.BAD] = 4
	scene._pm.counts[Judgement.Kind.MISS] = 6
	scene._pm.score = 51230
	scene._pm.max_combo = 87
	scene._pm.stop()
	scene._on_song_ended()
	await _wait(0.3)
	await _shoot("gui_resultados")
	scene.queue_free()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _tap(code: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
	await _wait(0.1)


func _shoot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://tests/shot_%s.png" % shot_name
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("captura %s -> %s" % [path, error_string(err)])
