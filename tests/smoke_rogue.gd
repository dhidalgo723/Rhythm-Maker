extends Node

## Modo roguelike: estructura de la partida, duraciones, dinero, tienda,
## consumibles, y que cada habilidad y mejora haga lo que dice.
## Correr: godot --headless --path . res://tests/smoke_rogue.tscn

const SEED := 1234
const Size := RogueCatalog.Size

var _failed := false
var _pool: RoguePool


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	_pool = RoguePool.load_pool()

	_test_sequence()
	_test_pool_durations()
	_test_combo_songs()
	_test_determinism()
	_test_prepare()
	_test_consumables()
	_test_arrows()
	_test_money()
	_test_shop()
	_test_every_ability()
	await _test_every_slot()
	_test_full_run()

	print("SMOKE TEST %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


## El Jefe Techno toca Coleccionista y el Rap Sax&Bass; los demas, la de
## prueba sin combinacion.
func _test_combo_songs() -> void:
	_check(_pool.problems.is_empty(), "pool.json sin problemas: %s" % ", ".join(_pool.problems))
	var want := {"techno": "coleccionista", "rap": "saxbass"}
	var seen := {}
	for seed in 400:
		var run := RogueRun.create(_pool, seed)
		var final := run.bosses[-1]
		var expected: String = want.get(final.combo_id, "prueba_jefe")
		_check(final.song_id == expected, "jefe %s: toca %s (deberia %s)" % [final.combo_id, final.song_id, expected])
		seen[final.combo_id] = true
	_check(seen.has("techno") and seen.has("rap"), "en 400 partidas salen Techno y Rap")
	print("[canciones] Techno = Coleccionista, Rap = Sax&Bass, el resto la de prueba")


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("  FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


func _run() -> RogueRun:
	return RogueRun.create(_pool, SEED)


# ---------------------------------------------------------------- Estructura

func _test_sequence() -> void:
	var seq := RogueCatalog.SEQUENCE
	_check(seq == [Size.SMALL, Size.MEDIUM, Size.MEDIUM, Size.BIG, Size.FINAL],
		"secuencia: Pequeno, Mediano, Mediano, Grande y Jefe")

	# El limite de cada cancion es el de su tamano.
	var limits: Array[int] = []
	for i in seq.size():
		limits.append(RogueCatalog.miss_limit(i))
	_check(limits == [5, 20, 20, 35, 30], "limites 5 / 20 / 20 / 35 / 30 (son %s)" % str(limits))
	# Lo que se pidio para cada tamano: duracion, notas, fallos y velocidad.
	var asked := {
		Size.SMALL: [30000, 40, 5, "lenta"],
		Size.MEDIUM: [60000, 60, 20, "media"],
		Size.BIG: [120000, 180, 35, "rapida"],
		Size.FINAL: [120000, 270, 30, "rapida"],   # 135 por minuto
	}
	for size in asked:
		var spec: Dictionary = RogueCatalog.SIZE_SPECS[size]
		var want: Array = asked[size]
		_check(spec["duration_ms"] == want[0] and spec["notes"] == want[1]
			and spec["misses"] == want[2] and spec["speed"] == want[3],
			"%s: %s" % [RogueCatalog.SIZE_NAMES[size], RogueCatalog.size_summary(size)])
	_check(RogueCatalog.travel_ms(Size.SMALL) > RogueCatalog.travel_ms(Size.MEDIUM)
		and RogueCatalog.travel_ms(Size.MEDIUM) > RogueCatalog.travel_ms(Size.BIG),
		"lenta > media > rapida: las notas tardan menos en caer cuanto mas grande el jefe")

	var targets: Array[int] = []
	for i in seq.size():
		targets.append(RogueCatalog.score_target(i, 100))
	for i in range(1, targets.size()):
		_check(targets[i] > targets[i - 1], "la puntuacion objetivo sube cancion a cancion")
	print("[secuencia] P M G x3 + G final | fallos %s" % str(limits))


## Lo que se pidio comprobar: que cada cancion dure lo de su jefe y tenga sus notas.
func _test_pool_durations() -> void:
	_check(_pool.problems.is_empty(), "pool.json con problemas: %s" % str(_pool.problems))
	_check(_pool.missing_sizes().is_empty(), "faltan canciones de: %s" % str(_pool.missing_sizes()))
	for song in _pool.songs:
		var entry: SongEntry = song["entry"]
		var size: Size = {"small": Size.SMALL, "medium": Size.MEDIUM, "big": Size.BIG,
			"boss": Size.FINAL}[song["size"]]
		var spec: Dictionary = RogueCatalog.SIZE_SPECS[size]
		var stream := AudioLoader.load_stream(entry.audio_path())
		_check(stream != null, "%s: no carga el audio" % song["id"])
		if stream == null:
			continue
		var audio_ms := stream.get_length() * 1000.0
		_check(audio_ms >= spec["duration_ms"], "%s: el audio (%.1f s) es mas corto que el jefe (%d s)" % [
			song["id"], audio_ms / 1000.0, spec["duration_ms"] / 1000])
		var count := entry.chart.notes.size()
		var last := entry.chart.notes[-1].end_ms()
		# Las notas exactas solo se exigen a los charts de prueba. Las canciones
		# grabadas tienen las que se grabaron, y se cortan a la duracion del jefe
		# al jugarlas.
		if str(song["id"]).begins_with("prueba_"):
			_check(count == spec["notes"], "%s: tiene %d notas, el jefe pide %d" % [song["id"], count, spec["notes"]])
			_check(last < spec["duration_ms"], "%s: hay notas despues de %d s" % [song["id"], spec["duration_ms"] / 1000])
		var per_min := float(count) / (float(spec["duration_ms"]) / 60000.0)
		print("  %-16s %-6s audio %6.1f s | jefe %3d s | %3d notas (%.0f/min) | ultima %.1f s" % [
			song["id"], song["size"], audio_ms / 1000.0, spec["duration_ms"] / 1000, count, per_min, last / 1000.0])
	print("[duraciones] cada cancion de prueba cumple la duracion y las notas de su jefe")


func _test_determinism() -> void:
	var a := _run()
	var b := _run()
	for i in a.bosses.size():
		_check(a.bosses[i].abilities == b.bosses[i].abilities and a.bosses[i].song_id == b.bosses[i].song_id,
			"misma semilla, mismo jefe %d" % i)
		_check(a.bosses[i].size == RogueCatalog.SEQUENCE[i], "el jefe %d tiene el tamano de la secuencia" % i)
		if a.bosses[i].size == Size.FINAL:
			_check(a.bosses[i].combo_id != "", "el jefe final tiene una combinacion")
		else:
			_check(a.bosses[i].abilities.size() == 1 and
				RogueCatalog.ABILITY[a.bosses[i].abilities[0]]["size"] == a.bosses[i].size,
				"el jefe %d tiene una habilidad de su tamano" % i)
		var visible := a.bosses[i].size in RogueCatalog.VISIBLE_SIZES
		_check(a.bosses[i].revealed == visible,
			"jefe %d: pequenos y medianos se ven, grandes y final empiezan ocultos" % i)
	print("[semilla] la misma semilla da la misma partida")


# ---------------------------------------------------------------- Cancion

func _test_prepare() -> void:
	for i in [0, 1, 3, 4]:
		var run := _run()
		run.index = i
		var boss := run.current_boss()
		boss.abilities.clear()   # sin jefe, para medir la cancion tal cual
		var p := run.prepare_song()
		_check(p != null, "la cancion %d se prepara" % i)
		if p == null:
			continue
		var spec := boss.spec()
		_check(is_equal_approx(p.length_ms, float(spec["duration_ms"])),
			"cancion %d: dura %.0f ms, el jefe pide %d" % [i, p.length_ms, spec["duration_ms"]])
		_check(p.chart.end_ms == spec["duration_ms"], "cancion %d: el chart acaba donde el jefe" % i)
		# Las notas de cada tamano son las que se piden a los charts de prueba;
		# las canciones grabadas tienen las que se grabaron.
		if boss.song_id.begins_with("prueba_"):
			_check(p.notes == spec["notes"], "cancion %d: %d notas jugables (pide %d)" % [i, p.notes, spec["notes"]])
		_check(p.target_score > 0 and p.target_score < p.notes * 350, "cancion %d: objetivo razonable (%d)" % [i, p.target_score])
		_check(p.rules.miss_limit == boss.miss_limit(), "cancion %d: limite de fallos del jefe" % i)
		_check(p.rules.travel_time_ms == RogueCatalog.travel_ms(boss.size), "cancion %d: velocidad del jefe" % i)
		_check(boss.revealed, "al empezar, el jefe se revela")
		_check(p.chart != p.entry.chart and p.entry.chart.end_ms != -1, "se juega una copia, no el chart guardado")
	print("[preparar] duracion, notas, objetivo y limite por tamano")


func _test_consumables() -> void:
	var run := _run()
	run.current_boss().abilities.assign(["ventana_estrecha"])
	run.pending.assign(["cuerdas", "contrato", "ensayo", "grabadora", "cascos_rotos", "soborno"])
	var base := run.current_boss().miss_limit()
	var p := run.prepare_song()
	_check(p.rules.miss_limit == base + 3 - 5, "Cuerdas +3 y Contrato -5 al limite (%d)" % p.rules.miss_limit)
	_check(is_equal_approx(p.money_mult, 2.0), "Contrato: dinero x2")
	_check(p.rules.risk_free_until_ms == 15000.0, "Ensayo: 15 s sin riesgo")
	_check(p.slot_uses == 2, "Grabadora: 2 usos")
	_check(p.rules.disabled_lanes.size() == 2, "Cascos Rotos: 2 flechas desactivadas")
	for lane in p.rules.disabled_lanes:
		_check(lane in Settings.DIRECTION_LANES, "Cascos Rotos desactiva flechas, no el espacio")
	_check(p.boss.bribed == "ventana_estrecha", "Soborno: desactiva la habilidad del jefe")
	_check(is_equal_approx(p.rules.perfect_window_mult, 1.0), "la habilidad sobornada no se aplica")
	_check(run.pending.is_empty(), "los consumibles se gastan al empezar la cancion")
	print("[consumibles] Cuerdas, Contrato, Ensayo, Grabadora, Cascos Rotos, Soborno")


func _test_arrows() -> void:
	var run := _run()
	run.current_boss().abilities.clear()
	run.arrows = {
		0: {"id": "dorada", "songs_left": 3},
		1: {"id": "cristal", "songs_left": -1},
		4: {"id": "gemela", "songs_left": -1},   # el espacio esta junto a Abajo
		2: {"id": "iman", "songs_left": -1},
		3: {"id": "hucha", "songs_left": -1},
	}
	var p := run.prepare_song()
	var r := p.rules
	_check(is_equal_approx(r.lane_score_mult[0], 1.75), "Dorada x1.75")
	_check(is_equal_approx(r.lane_score_mult[1], 2.5) and r.lane_miss_weight[1] == 2, "Cristal x2.5 y fallo doble")
	_check(RogueBuilder.twin_source(Lanes.SPACE) == 1, "la Gemela del espacio copia a Abajo (su izquierda)")
	_check(is_equal_approx(r.lane_score_mult[Lanes.SPACE], 2.5), "Gemela copia el x2.5 de su vecina")
	_check(is_equal_approx(r.lane_window_mult[2], 1.5), "Iman ventana x1.5")
	_check(is_equal_approx(r.lane_score_mult[3], 0.75) and 3 in r.coin_lanes, "Hucha x0.75 y da monedas")

	run = _run()
	run.current_boss().abilities.clear()
	run.arrows = {0: {"id": "escudo", "songs_left": -1}, 1: {"id": "maldita", "songs_left": -1},
		2: {"id": "hielo", "songs_left": -1}}
	r = run.prepare_song().rules
	_check(0 in r.shield_lanes, "Escudo")
	_check(1 in r.cursed_lanes and is_equal_approx(r.lane_score_mult[1], 3.0), "Maldita x3 e invisible al final")
	_check(2 in r.unbreakable_hold_lanes, "Hielo")
	print("[flechas] las 8 mejoras de flecha llegan a las reglas")


func _test_money() -> void:
	var run := _run()
	run.current_boss().abilities.clear()
	var p := run.prepare_song()
	var limit := p.rules.miss_limit
	var perfect_run := run.song_reward(p, {"misses": 0})
	var sloppy := run.song_reward(p, {"misses": limit})
	_check(perfect_run == RogueCatalog.REWARD_BASE[Size.SMALL] + RogueCatalog.REWARD_BONUS[Size.SMALL],
		"sin fallos se cobra todo (%d)" % perfect_run)
	_check(sloppy == RogueCatalog.REWARD_BASE[Size.SMALL], "al limite solo la base (%d)" % sloppy)
	_check(perfect_run > run.song_reward(p, {"misses": limit / 2}), "fallar menos da mas dinero")

	var coins := PackedInt32Array([0, 0, 0, 25, 0])
	_check(run.song_reward(p, {"misses": 0, "coin_perfects": coins}) == perfect_run + 2,
		"Hucha: 25 perfectos = 2 monedas extra")
	p.money_mult = 2.0
	_check(run.song_reward(p, {"misses": 0}) == perfect_run * 2, "Contrato: x2")
	p.money_mult = 1.0
	p.tax = 0.025
	_check(run.song_reward(p, {"misses": 0}) == perfect_run - 1, "Impuesto: se queda al menos 1 moneda")

	# Pasar y no pasar.
	p.tax = 0.0
	var out := run.finish_song(p, {"score": p.target_score, "misses": 0})
	_check(out["passed"] and run.money == perfect_run and run.index == 1, "pasar: cobras y avanzas")
	_check(run.state == RogueRun.State.SHOP and run.offers.size() == 3, "y abre la venta de garaje (3 cajas)")

	run = _run()
	p = run.prepare_song()
	out = run.finish_song(p, {"score": p.target_score - 1, "misses": 0})
	_check(not out["passed"] and run.state == RogueRun.State.LOST, "no llegar a la puntuacion pierde")
	run = _run()
	p = run.prepare_song()
	out = run.finish_song(p, {"score": 999999, "misses": 0, "lost": true})
	_check(out["boss_index"] == 0 and out["score"] == 999999 and out["miss_limit"] == p.rules.miss_limit,
		"el resultado guarda las cifras de la cancion para el mapa")
	_check(run.bosses_beaten == 0, "perder no suma jefes superados")
	_check(not out["passed"] and run.state == RogueRun.State.LOST, "pasarse de fallos pierde")
	print("[dinero] base + bono por fallos, Hucha, Contrato, Impuesto; ganar y perder")


func _test_shop() -> void:
	for kind in [RogueCatalog.ItemKind.SLOT, RogueCatalog.ItemKind.CONSUMABLE]:
		for id in RogueCatalog.table(kind):
			_check(RogueArt.image_path(kind, id) != "", "%s no tiene imagen" % id)
			_check(RogueArt.item_texture(kind, id, 64) != null, "la imagen de %s no se carga" % id)
	var run := _run()
	run.state = RogueRun.State.SHOP
	run.money = 100
	run.index = 3   # jefe grande: el unico que un Setlist tiene que revelar
	run.offers.assign([
		{"kind": RogueCatalog.ItemKind.SLOT, "id": "metronomo", "sold": false},
		{"kind": RogueCatalog.ItemKind.SLOT, "id": "pausa", "sold": false},
		{"kind": RogueCatalog.ItemKind.ARROW, "id": "dorada", "sold": false},
		{"kind": RogueCatalog.ItemKind.CONSUMABLE, "id": "cuerdas", "sold": false},
		{"kind": RogueCatalog.ItemKind.CONSUMABLE, "id": "setlist", "sold": false},
	])
	_check(run.buy(0) == "" and run.slot_id == "metronomo", "comprar una mejora de ranura")
	_check(run.buy(0) != "", "no se compra dos veces")
	_check(run.buy(1) == "" and run.slot_id == "pausa", "una ranura: la nueva sustituye a la anterior")
	_check(run.buy(2) != "", "una flecha sin elegir carril no se compra")
	_check(run.buy(2, 3) == "" and run.arrow_on(3) == "dorada", "la flecha se pone en el carril elegido")
	_check(run.buy(3) == "" and "cuerdas" in run.pending, "los consumibles quedan para la siguiente")
	var money_before := run.money
	_check(run.buy(4) == "" and run.current_boss().revealed, "Setlist revela el siguiente jefe")
	_check(run.money == money_before - 2, "Setlist cuesta 2")
	_check(run.offers.size() == 3 and not run.offers[0]["sold"], "y renueva las 3 cajas")

	run.money = 0
	_check(run.buy(0) == "No tienes dinero suficiente", "sin dinero no se compra")

	# La Dorada dura 3 canciones.
	for i in 3:
		run._age_arrows()
	_check(run.arrow_on(3) == "", "la Flecha Dorada se gasta tras 3 canciones")
	print("[tienda] ranura unica, flechas por carril, consumibles, Setlist, dinero")
	_test_shop_boxes()


## Lo que sale en cada caja: izquierda solo consumibles, centro 90% ranura,
## derecha 70% flecha. Se tira muchas veces y se mira la proporcion.
func _test_shop_boxes() -> void:
	var run := _run()
	var tally := [{}, {}, {}]
	var rolls := 2000
	for i in rolls:
		run.offers.clear()
		run.seed = i   # otra semilla, otras cajas
		run.roll_offers()
		var ids := {}
		for b in 3:
			var kind: int = run.offers[b]["kind"]
			tally[b][kind] = int(tally[b].get(kind, 0)) + 1
			_check(not ids.has(run.offers[b]["id"]), "una caja no repite el objeto de otra")
			ids[run.offers[b]["id"]] = true
	var K := RogueCatalog.ItemKind
	_check(tally[0].get(K.CONSUMABLE, 0) == rolls, "caja izquierda: siempre consumible")
	var center_slot := float(tally[1].get(K.SLOT, 0)) / rolls
	var right_arrow := float(tally[2].get(K.ARROW, 0)) / rolls
	_check(absf(center_slot - 0.9) < 0.04, "caja central: ~90%% ranura (%.0f%%)" % (center_slot * 100))
	_check(absf(right_arrow - 0.7) < 0.04, "caja derecha: ~70%% flecha (%.0f%%)" % (right_arrow * 100))
	_check(tally[1].get(K.CONSUMABLE, 0) == 0 and tally[2].get(K.CONSUMABLE, 0) == 0,
		"los consumibles solo salen en la izquierda")
	print("[cajas] izquierda consumible 100%%, centro ranura %.0f%%, derecha flecha %.0f%%" % [
		center_slot * 100, right_arrow * 100])

	# Lo comprado no vuelve a salir; sin consumibles por comprar, la caja
	# izquierda queda vacia.
	run = _run()
	for id in RogueCatalog.CONSUMABLE:
		if id != "setlist":
			run.purchased[RogueRun.item_key(K.CONSUMABLE, id)] = true
	run.purchased[RogueRun.item_key(K.SLOT, "metronomo")] = true
	for i in 200:
		run.seed = 5000 + i
		run.roll_offers()
		_check(run.offers[0]["id"] == "setlist", "solo queda el Setlist por comprar")
		_check(run.offers[1]["id"] != "metronomo" and run.offers[2]["id"] != "metronomo",
			"lo comprado no vuelve a salir")
	run.money = 100
	_check(run.buy(0) == "", "comprar el ultimo consumible")
	_check(run.offers[0]["id"] == "" and run.offers[0]["sold"],
		"sin nada que ofrecer, la caja izquierda queda vacia")
	print("[cajas] lo comprado no vuelve a salir")


# ---------------------------------------------------------------- Jefes

func _prepare_with(abilities: Array, index: int = 3) -> RoguePrepared:
	var run := _run()
	run.index = index
	run.current_boss().abilities.assign(abilities)
	return run.prepare_song()


func _test_every_ability() -> void:
	var original := _prepare_with([])
	var real_notes := original.notes

	for id in RogueCatalog.ABILITY:
		var p := _prepare_with([id])
		_check(p != null, "%s: la cancion se prepara" % id)
		if p == null:
			continue
		var r := p.rules
		var decoys := 0
		var doubles := 0
		var holds := 0
		for n in p.chart.notes:
			decoys += 1 if n.decoy else 0
			doubles += 1 if n.hits > 1 else 0
			holds += 1 if n.is_hold() else 0
		var base_holds := 0
		for n in original.chart.notes:
			base_holds += 1 if n.is_hold() else 0
		match id:
			"inversion":
				_check(_has_effect(r, TimedEffect.INVERT), "Inversion: tramo invertido")
			"crescendo":
				_check(r.crescendo_to > 1.0, "Crescendo: acelera")
			"ondulada":
				_check(r.wave, "Pista Ondulada")
			"zoom":
				_check(r.zoom, "Zoom de Camara")
			"ritardando":
				var e := _effect(r, TimedEffect.TEMPO)
				_check(e != null and is_equal_approx(e.start_ms, p.length_ms * 0.5) and float(e.data["tempo"]) < 1.0,
					"Ritardando: el tempo baja a mitad de cancion")
			"doble_golpe":
				_check(doubles > 0, "Doble Golpe: hay notas de 2 golpes (%d)" % doubles)
			"impuesto":
				_check(p.tax > 0.0, "Impuesto")
			"senuelos":
				_check(decoys > 0 and p.notes == real_notes, "Senuelos: %d senuelos y las notas reales intactas" % decoys)
			"abucheo":
				_check(r.scroll_per_miss > 0.0, "Abucheo")
			"acoplamiento":
				var e := _effect(r, TimedEffect.SLOT_BLOCKED)
				_check(e != null and is_equal_approx(e.end_ms - e.start_ms, p.length_ms * 0.2), "Acoplamiento: 20% bloqueado")
			"pista_invertida":
				_check(_has_effect(r, TimedEffect.REVERSE), "Pista Invertida")
			"camufladas":
				_check(r.camouflage, "Notas Camufladas")
			"silencio":
				_check(_has_effect(r, TimedEffect.SILENCE), "Silencio")
			"cuerda_rota":
				_check(r.disabled_lanes.size() == 1, "Cuerda Rota: un carril roto")
				var broken := r.disabled_lanes[0]
				var left := 0
				for n in p.chart.notes:
					left += 1 if n.lane == broken else 0
				_check(left == 0, "Cuerda Rota: el carril roto no tiene notas")
				_check(p.notes >= real_notes - 5, "Cuerda Rota: las notas se reparten, casi no se pierden (%d de %d)" % [p.notes, real_notes])
			"escudo_jefe":
				_check(r.boss_shield_perfects == 5, "Escudo del Jefe: 5 perfectos")
			"ventana_estrecha":
				_check(is_equal_approx(r.perfect_window_mult, 0.5), "Ventana Estrecha: perfecto a la mitad")
			"saqueador":
				_check(r.steal_after_misses == 5, "Saqueador: 5 fallos seguidos")
			"carril_minado":
				_check(decoys > 0 and p.notes < real_notes, "Carril Minado: notas convertidas en senuelos (%d)" % decoys)
			"fantasma":
				_check(r.ghost, "Notas Fantasma")
			"teclas_mezcladas":
				var e := _effect(r, TimedEffect.SHUFFLE_NOTES)
				_check(e != null and is_equal_approx(e.end_ms - e.start_ms, p.length_ms * RogueCatalog.BOSS_SEGMENT),
					"Teclas Mezcladas: un tramo del 20%")
				if e != null:
					var inside := 0
					var moved := 0
					var outside_moved := 0
					for n in p.chart.notes:
						if e.is_active(n.timestamp_ms):
							inside += 1
							if n.show_lane >= 0 and n.show_lane != n.lane:
								moved += 1
						elif n.show_lane >= 0:
							outside_moved += 1
					_check(inside > 0 and moved >= inside * 0.8,
						"Teclas Mezcladas: las notas del tramo caen por otra columna (%d de %d)" % [moved, inside])
					_check(outside_moved == 0, "Teclas Mezcladas: fuera del tramo, cada nota por su carril")
					# Las que caen a la vez, por columnas distintas.
					var at := {}
					for n in p.chart.notes:
						if n.show_lane >= 0:
							var k := "%d:%d" % [n.timestamp_ms, n.show_lane]
							_check(not at.has(k), "Teclas Mezcladas: dos notas a la vez por la misma columna")
							at[k] = true
			"rasgueo":
				_check(holds > base_holds and p.notes > real_notes,
					"Rasgueo: las largas se parten en trozos (%d largas, antes %d)" % [holds, base_holds])
			"polirritmia":
				_check(_has_triplets(p.chart), "Polirritmia: un carril en tresillos")
			"pegajosas":
				_check(holds > base_holds + 3, "Notas Pegajosas: muchas largas (%d, antes %d)" % [holds, base_holds])
			"maldicion":
				_check(r.cursed_lanes.size() == 1, "Maldicion: una flecha maldita")
	# El jefe final combina las suyas.
	for combo in RogueCatalog.FINAL_COMBOS:
		var abilities: Array = RogueCatalog.FINAL_COMBOS[combo]["abilities"]
		var p := _prepare_with(abilities, 4)
		_check(p != null and p.boss.active_abilities().size() == abilities.size(),
			"jefe final %s: %d habilidades" % [combo, abilities.size()])
	print("[jefes] las %d habilidades y los %d jefes finales se aplican" % [
		RogueCatalog.ABILITY.size(), RogueCatalog.FINAL_COMBOS.size()])


func _has_effect(r: PlayRules, id: String) -> bool:
	return _effect(r, id) != null


func _effect(r: PlayRules, id: String) -> TimedEffect:
	for e in r.effects:
		if e.id == id:
			return e
	return null


## Hay notas fuera de la rejilla de negras, en tercios de beat?
func _has_triplets(chart: Chart) -> bool:
	var third := chart.beat_ms() / 3.0
	for n in chart.notes:
		var k := (n.timestamp_ms - chart.beat_offset_ms) / third
		if absf(k - roundf(k)) < 0.05 and int(roundf(k)) % 3 != 0:
			return true
	return false


# ---------------------------------------------------------------- Ranura

## Cada mejora de ranura se activa en una partida real y hace su efecto.
func _test_every_slot() -> void:
	for id in RogueCatalog.SLOT:
		var run := _run()
		run.current_boss().abilities.clear()
		run.slot_id = id
		var p := run.prepare_song()
		var pm := PlaybackManager.new()
		add_child(pm)
		var rt := RogueRuntime.new()
		add_child(rt)
		rt.setup(run, p, pm)
		pm.start(p.stream, p.chart, p.rules)
		await get_tree().create_timer(0.3).timeout

		var t := pm.get_time_ms()
		var effects_before := pm.rules.effects.size()
		var why := rt.activate()
		if id == "bis":
			_check(why != "" and p.rules.bis, "Bis no se activa a mano: va en las reglas")
		else:
			_check(why == "", "%s deberia activarse (%s)" % [id, why])
			_check(rt.uses_left == 0, "%s gasta su uso" % id)
			_check(rt.activate() != "", "%s no se puede usar dos veces" % id)
		match id:
			"fast_forward":
				_check(pm.get_time_ms() > t + p.length_ms * 0.04, "Fast Forward adelanta un 5%")
			"pausa":
				_check(pm.clock.is_paused(), "Pausa para la cancion")
			"casete":
				_check(pm.get_time_ms() < t + 50.0, "Cinta rebobina")
			"pad_dj", "arreglo", "bis":
				pass
			_:
				_check(pm.rules.effects.size() > effects_before, "%s anade su efecto" % id)
		pm.stop()
		pm.queue_free()
		rt.queue_free()
		await get_tree().process_frame

	# Grabadora: 2 usos. Acoplamiento: bloqueada.
	var run2 := _run()
	run2.current_boss().abilities.clear()
	run2.slot_id = "afinador"
	run2.pending.assign(["grabadora"])
	var p2 := run2.prepare_song()
	var pm2 := PlaybackManager.new()
	add_child(pm2)
	var rt2 := RogueRuntime.new()
	add_child(rt2)
	rt2.setup(run2, p2, pm2)
	pm2.start(p2.stream, p2.chart, p2.rules)
	await get_tree().create_timer(0.2).timeout
	_check(rt2.activate() == "" and rt2.activate() == "", "Grabadora: dos usos")
	_check(rt2.activate() != "", "y no un tercero")
	pm2.add_effect(TimedEffect.SLOT_BLOCKED, 0.0, 999999.0)
	rt2.uses_left = 1
	_check(rt2.activate().contains("bloqueada"), "Acoplamiento bloquea la ranura")
	pm2.slot_stolen.emit()
	_check(run2.slot_id == "", "Saqueador: la mejora desaparece de la partida")
	pm2.stop()
	pm2.queue_free()
	rt2.queue_free()
	print("[ranura] las %d mejoras se activan una vez; Grabadora, Acoplamiento y Saqueador" % RogueCatalog.SLOT.size())


# ---------------------------------------------------------------- Partida

func _test_full_run() -> void:
	var run := _run()
	var visited_shops := 0
	var total := run.songs_total()
	for i in total:
		var p := run.prepare_song()
		_check(p != null, "la cancion %d se prepara" % (i + 1))
		if p == null:
			return
		run.finish_song(p, {"score": p.target_score, "misses": 0})
		if run.state == RogueRun.State.SHOP:
			visited_shops += 1
			run.state = RogueRun.State.MAP
	_check(total == 5, "una partida son 5 canciones")
	_check(run.state == RogueRun.State.WON, "tras %d canciones superadas se gana" % total)
	_check(visited_shops == total - 1, "hay venta de garaje entre cancion y cancion (%d)" % visited_shops)
	print("[partida] %d canciones superadas = victoria, con %d visitas a la tienda" % [total, visited_shops])
