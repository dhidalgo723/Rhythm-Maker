extends Node

## Verifica los idiomas:
##   1. cambiar de idioma traduce, y en espanol los textos salen tal cual
##   2. cada Lang.t("...") del codigo tiene traduccion al ingles, con los
##      mismos %d / %s en el mismo orden
##   3. las tablas de nombres (catalogo, carriles, juicios...) tambien
##   4. Ajustes funciona en ingles: pestanas, Informacion e idioma
## Correr: godot --headless --path . res://tests/smoke_lang.tscn

## Huecos de formato que tienen que coincidir: %d, %s, %+d, %.1f, %02d...
## (sin el flag de espacio, para no confundir "5% de" con un hueco).
const FORMAT := "%[+]?\\d*(?:\\.\\d+)?[dsf]"

var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioServer.set_bus_mute(0, true)
	var original := Settings.language
	await get_tree().process_frame

	_test_switch()
	_test_sources()
	_test_tables()
	await _test_settings_in_english()

	Lang.apply(original)
	print("SMOKE TEST %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("  FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


# --- 1 ---
func _test_switch() -> void:
	Lang.apply("en")
	_check(Lang.t("Volver") == "Back", "en ingles, Volver deberia ser Back (es %s)" % Lang.t("Volver"))
	_check(Lanes.lane_name(0) == "Left", "en ingles, el carril 0 deberia ser Left")
	_check(RogueCatalog.item_name(RogueCatalog.ItemKind.ARROW, "dorada") == "Golden Arrow",
		"los nombres del catalogo deberian traducirse")
	Lang.apply("es")
	# Sin locale/fallback = "es" en project.godot, Godot usaria la traduccion
	# inglesa tambien aqui.
	_check(Lang.t("Volver") == "Volver", "en espanol, Volver deberia quedarse igual (es %s)" % Lang.t("Volver"))
	_check(Lang.t("texto sin traduccion") == "texto sin traduccion", "un texto sin traduccion deberia salir tal cual")
	print("[cambio] ingles y espanol")


# --- 2 ---
func _test_sources() -> void:
	var call := RegEx.create_from_string("Lang\\.t\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var count := 0
	for path in _scripts("res://scripts"):
		var source := FileAccess.get_file_as_string(path)
		for m in call.search_all(source):
			var key := m.get_string(1).c_unescape()
			count += 1
			_check_key(key, path.get_file())
	_check(count > 200, "deberia haber muchos Lang.t() en el codigo (hay %d)" % count)
	print("[codigo] %d textos con traduccion" % count)


func _check_key(key: String, where: String) -> void:
	if not LangEn.TEXT.has(key):
		_check(false, "%s: falta la traduccion de \"%s\"" % [where, key])
		return
	var format := RegEx.create_from_string(FORMAT)
	var a: Array[String] = []
	var b: Array[String] = []
	for m in format.search_all(key):
		a.append(m.get_string())
	for m in format.search_all(LangEn.TEXT[key]):
		b.append(m.get_string())
	_check(a == b, "%s: \"%s\" y su traduccion no tienen los mismos huecos (%s / %s)" % [where, key, a, b])


func _scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(sub)))
	return out


# --- 3 ---
func _test_tables() -> void:
	var names: Array[String] = []
	for table in [RogueCatalog.SLOT, RogueCatalog.ARROW, RogueCatalog.CONSUMABLE, RogueCatalog.ABILITY]:
		for id in table:
			names.append(table[id]["name"])
			names.append(table[id]["desc"])
	for id in RogueCatalog.FINAL_COMBOS:
		names.append(RogueCatalog.FINAL_COMBOS[id]["name"])
	for table in [RogueCatalog.SIZE_NAMES, RogueCatalog.SPEED_NAMES, RogueCatalog.KIND_NAMES,
			Judgement.NAMES, InfoText.TITLES, RogueHud.EFFECT_NAMES]:
		for k in table:
			names.append(table[k])
	names.append_array(Lanes.NAMES)
	names.append_array(Settings.SLOT_NAMES)
	for preset_name in Settings.PRESETS:
		if preset_name not in ["WASD", "DFJK"]:   # se llaman igual en los dos idiomas
			names.append(preset_name)
	names.append_array(["pronto", "tarde"])
	for n in names:
		_check(LangEn.TEXT.has(n), "tablas: falta la traduccion de \"%s\"" % n)
	print("[tablas] %d nombres con traduccion" % names.size())


# --- 4 ---
func _test_settings_in_english() -> void:
	Lang.apply("en")
	var scene: Control = load("res://scenes/settings_scene.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	_check(scene._controls.visible != scene._info.visible, "solo una pestana a la vez")
	scene._on_tab_pressed(scene.Tab.INFO)
	await get_tree().process_frame
	_check(scene._info.visible and not scene._controls.visible, "la pestana Informacion se abre")
	for i in InfoText.CATEGORIES.size():
		scene._show_category(i)
		_check(scene._info_text.text.length() > 40, "la categoria %s tiene texto" % InfoText.CATEGORIES[i])
		_check(not "Durante" in scene._info_text.text, "la categoria %s deberia estar en ingles" % InfoText.CATEGORIES[i])
	scene._on_tab_pressed(scene.Tab.CONTROLS)
	_check(scene._controls.visible, "se vuelve a Controles")
	_check((scene._tab_buttons[0] as Button).text == "CONTROLS", "las pestanas salen en ingles")
	scene._last_tab = scene.Tab.CONTROLS
	scene.queue_free()
	await get_tree().process_frame
	print("[ajustes] pestanas e informacion en ingles")
