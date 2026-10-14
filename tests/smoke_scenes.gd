extends Node

## Instancia TODAS las escenas y las deja correr unos frames.
##
## Existe porque `--editor --quit` compila los scripts de forma perezosa: un
## script que solo se instancia en runtime (PlayField) puede tener un error de
## parseo y aun asi pasar el import sin decir nada. Aqui se ejecuta de verdad.
##
## Correr: godot --headless --path . res://tests/smoke_scenes.tscn
## Falla la build si la salida contiene "SCRIPT ERROR".

const SCENES := [
	"res://scenes/main_menu.tscn",
	"res://scenes/edit_menu.tscn",
	"res://scenes/song_select.tscn",
	"res://scenes/settings_scene.tscn",
	"res://scenes/calibration_scene.tscn",
	"res://scenes/recording_scene.tscn",
	"res://scenes/play_scene.tscn",
	"res://scenes/rogue_menu.tscn",
	"res://scenes/rogue_shop.tscn",
]

const FRAMES_PER_SCENE := 30


func _ready() -> void:
	# Contexto para que las escenas tomen su camino normal y no el early-return.
	var songs := Library.list_songs()
	if songs.is_empty():
		print("AVISO: biblioteca vacia, play_scene no se probara a fondo")
	else:
		Session.selected_song = songs[0]
	Session.recording_title = "smoke"
	# La tienda y el mapa del roguelike necesitan una partida en curso: sin
	# ella la tienda se va sola al menu (y se llevaria por delante este test).
	var run := RogueRun.create(RoguePool.load_pool(), 1)
	run.state = RogueRun.State.SHOP
	run.money = 10
	run.roll_offers()
	Session.rogue_run = run
	Session.set_audio(ProjectSettings.globalize_path("res://tests/test_tone.wav"))

	for path in SCENES:
		await _run_scene(path)

	Session.rogue_run = null
	print("SCENES OK")
	get_tree().quit(0)


func _run_scene(path: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("no carga %s" % path)
		print("  %s -> NO CARGA" % path)
		return

	var inst: Node = packed.instantiate()
	add_child(inst)
	for i in FRAMES_PER_SCENE:
		await get_tree().process_frame

	# Comprobacion basica de que la UI se construyo: algo tiene que haber dentro.
	var children := inst.get_child_count()
	print("  %-38s ok, %d nodos hijos" % [path.get_file(), children])
	if children == 0:
		push_error("%s no construyo ninguna UI" % path)

	inst.queue_free()
	await get_tree().process_frame
