extends Node

## Capturas de calibracion, pausa y cuenta atras de grabacion.
## Correr: godot --path . res://tests/capture_features.tscn

const TONE := "res://tests/test_tone.wav"


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	# La pausa congela el arbol; sin esto la corrutina de captura se congelaria
	# con el y no llegaria a guardar nada.
	process_mode = Node.PROCESS_MODE_ALWAYS

	await _capture_calibration()
	await _capture_recording_countdown()
	await _capture_pause()
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://tests/shot_%s.png" % name
	var err := get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path(path))
	print("captura %s -> %s" % [path, error_string(err)])


func _capture_calibration() -> void:
	var inst: Control = load("res://scenes/calibration_scene.tscn").instantiate()
	add_child(inst)
	await _wait(0.4)
	inst._on_start()          # arranca el metronomo
	await _wait(2.2)
	# Toques simulados para que la pantalla muestre progreso real.
	var cal: CalibrationManager = inst._cal
	for i in 8:
		cal.register_tap(cal.beat_ms() * (CalibrationManager.LEAD_BEATS + i) + 38.0)
	await _wait(0.3)
	await _shoot("calibracion")
	inst._cal.stop()
	inst.queue_free()
	await _wait(0.2)


func _capture_recording_countdown() -> void:
	Session.recording_title = "captura"
	Session.set_audio(ProjectSettings.globalize_path(TONE))
	var inst: Control = load("res://scenes/recording_scene.tscn").instantiate()
	add_child(inst)
	await _wait(1.2)          # aun en cuenta atras
	await _shoot("grabacion_cuenta")
	inst.queue_free()
	await _wait(0.2)


func _capture_pause() -> void:
	var songs := Library.list_songs()
	if songs.is_empty():
		print("sin canciones, me salto la pausa")
		return
	Session.selected_song = songs[0]

	var inst: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(inst)
	await _wait(5.0)          # cuenta atras (3 s) + unos segundos de juego
	inst._set_paused(true)
	await _wait(0.3)
	await _shoot("pausa")
	inst._set_paused(false)
	inst._pm.stop()
	inst.queue_free()
	await _wait(0.2)
