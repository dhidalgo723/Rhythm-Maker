extends Node

## Captura el menu principal y la pantalla de Ajustes.
## Correr: godot --path . res://tests/capture_settings.tscn


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	await _shoot("res://scenes/main_menu.tscn", "menu")
	await _shoot("res://scenes/settings_scene.tscn", "ajustes")
	get_tree().quit(0)


func _shoot(scene: String, name: String) -> void:
	var inst: Node = load(scene).instantiate()
	add_child(inst)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://tests/shot_%s.png" % name
	var err := get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path(path))
	print("captura %s -> %s" % [path, error_string(err)])
	inst.queue_free()
	await get_tree().process_frame
