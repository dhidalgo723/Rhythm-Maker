extends Node

## Capturas de Ajustes (Controles e Informacion) y de varias pantallas en los
## dos idiomas. El idioma solo cambia en memoria: settings.cfg no se toca.
## Correr: godot --path . --disable-vsync res://tests/capture_lang.tscn

const SEED := 7


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioServer.set_bus_mute(0, true)
	var original := Settings.language

	for code in Lang.CODES:
		Lang.apply(code)
		await _scene_shot("main_menu", "lang_%s_menu" % code)
		await _settings_shots(code)

		var run := RogueRun.create(RoguePool.load_pool(), SEED)
		run.money = 9
		Session.rogue_run = run
		await _scene_shot("rogue_menu", "lang_%s_mapa" % code)
		# Despues de pasar la primera: el mapa ensena como fue.
		var p := run.prepare_song()
		run.finish_song(p, {"score": p.target_score + 1720, "misses": 3, "accuracy": 94.3,
			"perfects": 31, "max_combo": 22})
		run.slot_id = "metronomo"
		run.arrows = {0: {"id": "dorada", "songs_left": 2}}
		run.pending.assign(["cuerdas"])
		await _scene_shot("rogue_menu", "lang_%s_mapa_tras_cancion" % code)
		run.state = RogueRun.State.SHOP
		run.money = 30
		run.offers.assign([
			{"kind": RogueCatalog.ItemKind.CONSUMABLE, "id": "cuerdas", "sold": false},
			{"kind": RogueCatalog.ItemKind.SLOT, "id": "tocadiscos", "sold": false},
			{"kind": RogueCatalog.ItemKind.ARROW, "id": "hielo", "sold": false},
		])
		var shop: Node = load("res://scenes/rogue_shop.tscn").instantiate()
		add_child(shop)
		await _wait(0.4)
		shop._boxes[1].grab_focus()
		await _wait(0.2)
		await _shoot("lang_%s_tienda" % code)
		shop.queue_free()
		Session.rogue_run = null
		await _wait(0.1)

	Lang.apply(original)
	get_tree().quit(0)


func _settings_shots(code: String) -> void:
	var scene: Node = load("res://scenes/settings_scene.tscn").instantiate()
	add_child(scene)
	await _wait(0.4)
	await _shoot("lang_%s_ajustes_controles" % code)
	scene._on_tab_pressed(scene.Tab.INFO)
	scene._category_buttons[3].grab_focus()   # jefes medianos
	await _wait(0.3)
	await _shoot("lang_%s_ajustes_info" % code)
	scene._category_buttons[0].grab_focus()   # puntuacion
	await _wait(0.3)
	await _shoot("lang_%s_ajustes_puntuacion" % code)
	scene._last_tab = scene.Tab.CONTROLS
	scene._last_category = 0
	scene.queue_free()
	await _wait(0.1)


func _scene_shot(scene_name: String, shot_name: String) -> void:
	var scene: Node = load("res://scenes/%s.tscn" % scene_name).instantiate()
	add_child(scene)
	await _wait(0.4)
	await _shoot(shot_name)
	scene.queue_free()
	await _wait(0.1)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shoot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://tests/shot_%s.png" % shot_name
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("captura %s -> %s" % [path, error_string(err)])
