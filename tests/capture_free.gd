extends Node

## Capturas de Juego Libre con habilidades: la pregunta, la lista de
## habilidades y una partida con ellas. Tambien el mapa del roguelike.
## Correr: godot --path . --disable-vsync res://tests/capture_free.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioServer.set_bus_mute(0, true)
	var entry: SongEntry = RoguePool.load_pool().find("prueba_grande")["entry"]

	var select: Control = load("res://scenes/song_select.tscn").instantiate()
	add_child(select)
	await _wait(0.4)
	select._on_play(entry)
	await _wait(0.3)
	await _shoot("libre_1_pregunta")
	Session.free_abilities.assign(["ondulada", "senuelos", "teclas_mezcladas"])
	select._open_abilities()
	await _wait(0.2)
	(select._ability_buttons["rasgueo"] as Button).grab_focus()
	select._toggle_ability("rasgueo")
	await _wait(0.3)
	await _shoot("libre_2_habilidades")
	select.queue_free()
	await _wait(0.1)

	Session.selected_song = entry
	Session.free_abilities.assign(["ondulada", "senuelos", "rasgueo", "cuerda_rota"])
	var scene: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(scene)
	await _wait(5.0)
	await _shoot("libre_3_partida")
	scene._pm.stop()
	scene.queue_free()
	Session.free_abilities.assign([])
	await _wait(0.2)

	Session.rogue_run = RogueRun.create(RoguePool.load_pool(), 7)
	var map: Node = load("res://scenes/rogue_menu.tscn").instantiate()
	add_child(map)
	await _wait(0.4)
	await _shoot("libre_4_mapa_5_canciones")
	Session.rogue_run = null
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shoot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://tests/shot_%s.png" % shot_name
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("captura %s -> %s" % [path, error_string(err)])
