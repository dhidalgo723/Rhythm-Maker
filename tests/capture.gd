extends Node

## Arranca el modo juego y guarda capturas, para revisar el playfield sin jugar.
## Correr: godot --path . res://tests/capture.tscn
## Silencia el bus master: aqui solo interesa la imagen.

const SHOTS := [4.2, 5.6, 7.0]


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var songs := Library.list_songs()
	if songs.is_empty():
		print("no hay canciones"); get_tree().quit(1); return
	Session.selected_song = songs[0]

	# Instanciar como hijo, no change_scene_to_file: si cambiamos de escena
	# este nodo se libera y la corrutina de captura muere en silencio.
	add_child(load("res://scenes/play_scene.tscn").instantiate())

	var t := 0.0
	var shot := 0
	while shot < SHOTS.size():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t >= SHOTS[shot]:
			await RenderingServer.frame_post_draw
			var path := "res://tests/shot_%d.png" % shot
			var err := get_viewport().get_texture().get_image().save_png(
				ProjectSettings.globalize_path(path))
			print("captura %s a los %.1f s -> %s" % [path, t, error_string(err)])
			shot += 1
	get_tree().quit(0)
