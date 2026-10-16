extends Node

## Capturas del modo roguelike, de la portada a la venta de garaje.
## Correr: godot --path . --disable-vsync res://tests/capture_rogue.tscn

const SEED := 7


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioServer.set_bus_mute(0, true)
	Session.rogue_run = null
	# Solo en memoria, para que haya notas en pantalla en cada foto. No se
	# guarda: la preferencia del jugador en settings.cfg no se toca.
	Settings.travel_time_ms = 1500

	await _scene_shot("main_menu", "rogue_0_menu_principal")
	await _scene_shot("rogue_menu", "rogue_1_portada")

	var run := RogueRun.create(RoguePool.load_pool(), SEED)
	run.money = 9
	run.slot_id = "metronomo"
	run.arrows = {0: {"id": "dorada", "songs_left": 3}, 3: {"id": "cristal", "songs_left": -1}}
	run.pending.assign(["cuerdas"])
	Session.rogue_run = run
	await _scene_shot("rogue_menu", "rogue_2_mapa")

	# Partida: jefe con efectos que se vean en una captura.
	run.current_boss().abilities.assign(["senuelos", "doble_golpe"])
	await _play_shots(run)

	# Venta de garaje: lo que salga, con la primera caja seleccionada.
	await _scene_shot("rogue_shop", "rogue_5_tienda")

	# Cajas fijas para ver los tres tipos: consumible, ranura y flecha.
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
	await _shoot("rogue_5b_caja_seleccionada")
	shop._on_box_pressed(0)          # comprar el consumible: queda la X
	shop._boxes[2].grab_focus()
	await _wait(0.2)
	await _shoot("rogue_5c_comprado")
	shop._on_box_pressed(2)          # la flecha pide carril
	await _wait(0.4)
	await _shoot("rogue_6_elegir_flecha")
	shop.queue_free()

	# Efectos visuales grandes: pista invertida, camufladas y notas largas.
	run.state = RogueRun.State.MAP
	run.current_boss().abilities.assign(["pegajosas", "camufladas"])
	await _play_reverse(run)
	await _note_kinds()
	await _shuffled_columns()

	get_tree().quit(0)


## Una nota de cada tipo para ver como se dibujan: larga, senuelo, doble golpe.
func _note_kinds() -> void:
	Session.rogue_prepared = null
	var e := SongEntry.new()
	e.slug = "tipos"
	e.dir = ProjectSettings.globalize_path("res://tests")
	e.chart = Chart.new()
	e.chart.title = "Tipos de nota"
	e.chart.song_path = "test_tone.wav"
	e.chart.add_note(1300, 0, 900)                 # larga
	e.chart.add_note(1500, 1).hits = 2             # doble golpe
	e.chart.add_note(1700, 2).decoy = true         # senuelo
	e.chart.add_note(1900, 3)                      # normal
	e.chart.add_note(2100, Lanes.SPACE, 600)       # larga en el espacio
	Session.selected_song = e
	var scene: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(scene)
	await _wait(3.6)
	await _shoot("rogue_8_tipos_de_nota")
	scene._pm.stop()
	scene.queue_free()
	await _wait(0.2)


## Teclas Mezcladas: cada flecha cae por otra columna, con su propio icono.
func _shuffled_columns() -> void:
	Session.rogue_prepared = null
	var e := SongEntry.new()
	e.slug = "mezcladas"
	e.dir = ProjectSettings.globalize_path("res://tests")
	e.chart = Chart.new()
	e.chart.title = "Teclas Mezcladas"
	e.chart.song_path = "test_tone.wav"
	var columns := {0: Lanes.SPACE, 1: 3, Lanes.SPACE: 0, 2: 1, 3: 2}
	var t := 1500
	for lane in [0, 1, Lanes.SPACE, 2, 3]:
		e.chart.add_note(t, lane).show_lane = columns[lane]
		t += 150
	Session.selected_song = e
	var scene: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(scene)
	await _wait(3.6)
	await _shoot("rogue_8b_columnas_mezcladas")
	scene._pm.stop()
	scene.queue_free()
	await _wait(0.2)


func _play_shots(run: RogueRun) -> void:
	Session.rogue_prepared = run.prepare_song()
	var scene: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(scene)
	await _wait(3.2)
	await _bot(scene, 2.6)
	await _shoot("rogue_3_jugando")

	scene._rogue.activate()   # Metronomo
	await _bot(scene, 0.5)
	await _shoot("rogue_3b_mejora_activada")

	# Resultado: superado.
	scene._pm.score = Session.rogue_prepared.target_score + 1234
	scene._pm.stop()
	scene._show_rogue_results(false)
	await _wait(0.4)
	await _shoot("rogue_4_superado")
	Session.rogue_prepared = null
	scene.queue_free()
	await _wait(0.2)


func _play_reverse(run: RogueRun) -> void:
	var prepared := run.prepare_song()
	Session.rogue_prepared = prepared
	var scene: Control = load("res://scenes/play_scene.tscn").instantiate()
	add_child(scene)
	await _wait(3.2)
	# Los tramos del jefe caen en momentos al azar: para la foto, desde ya.
	scene._pm.add_effect(TimedEffect.REVERSE, 0.0, 999999.0)
	scene._pm.add_effect(TimedEffect.INVERT, 0.0, 999999.0)
	await _bot(scene, 3.4)   # la mediana tiene un hueco entre 1,6 s y 4,0 s
	await _shoot("rogue_7_invertida_camufladas")
	# Teclas Mezcladas: bajo cada receptor, la tecla que ahora lo activa.
	# Sin camufladas ni pista invertida, para que se vea cada flecha en otra columna.
	scene._pm.rules.camouflage = false
	scene._pm.rules.effects.clear()
	scene._pm.add_effect(TimedEffect.SHUFFLE_NOTES, 0.0, 999999.0)
	ChartTransforms.shuffle_columns(scene._pm.chart, 0.0, 999999.0, RandomNumberGenerator.new(), [])
	await _bot(scene, 1.2)
	await _shoot("rogue_7b_teclas_mezcladas")
	scene._pm.stop()
	Session.rogue_prepared = null
	scene.queue_free()
	await _wait(0.2)


## Toca las notas a su tiempo, sin senuelos, directamente en el manager.
func _bot(scene: Control, seconds: float) -> void:
	var pm: PlaybackManager = scene._pm
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		if not pm.is_active():
			continue
		var t := pm.get_time_ms()
		for lane in Lanes.COUNT:
			for pn: PlayNote in pm.lane_notes(lane):
				if pn.state == PlayNote.State.PENDING and not pn.note.decoy and pn.time_ms <= t:
					for i in pn.note.hits - pn.hits_done:
						pm.judge_press(lane, pn.time_ms)
				elif pn.state == PlayNote.State.HOLDING and pn.note.end_ms() <= t:
					pm.judge_release(lane, pn.note.end_ms())


func _scene_shot(scene_name: String, shot_name: String) -> void:
	var scene: Node = load("res://scenes/%s.tscn" % scene_name).instantiate()
	add_child(scene)
	await _wait(0.5)
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
