class_name RogueBuilder
extends RefCounted

## Monta la cancion actual de una partida: corta el chart a la duracion del
## jefe y le aplica consumibles, flechas mejoradas, la ranura y las
## habilidades del jefe. El resultado es un RoguePrepared listo para jugar.

## Ensayo: segundos sin riesgo al principio.
const REHEARSAL_MS := 15000.0
## Notas Pegajosas ocupan un tramo algo mas largo que el resto.
const STICKY_SEGMENT := 0.25


static func build(run: RogueRun) -> RoguePrepared:
	var boss := run.current_boss()
	if boss == null:
		return null
	var song := run.pool.find(boss.song_id) if run.pool != null else {}
	if song.is_empty():
		push_error("No hay cancion para el jefe %d (%s)" % [boss.index, boss.song_id])
		return null

	var p := RoguePrepared.new()
	p.boss = boss
	p.entry = song["entry"]
	p.stream = AudioLoader.load_stream(p.entry.audio_path())
	if p.stream == null:
		return null

	# --- Duracion del jefe ---
	var spec := boss.spec()
	p.length_ms = minf(float(spec["duration_ms"]), p.stream.get_length() * 1000.0)
	p.chart = p.entry.chart.duplicate_chart()
	p.chart.end_ms = roundi(p.length_ms)
	var inside: Array[ChartNote] = []
	for n in p.chart.notes:
		if n.timestamp_ms < p.length_ms:
			n.duration_ms = mini(n.duration_ms, roundi(p.length_ms) - n.timestamp_ms)
			inside.append(n)
	p.chart.notes = inside

	p.rules = PlayRules.new()
	p.rules.miss_limit = boss.miss_limit()
	p.rules.travel_time_ms = RogueCatalog.travel_ms(boss.size)

	_apply_consumables(run, p)
	_apply_arrows(run, p)
	if run.slot_id == "bis":
		p.rules.bis = true
	_apply_boss(run, p)

	p.rules.miss_limit = maxi(1, p.rules.miss_limit)
	p.notes = 0
	for n in p.chart.notes:
		if not n.decoy and not n.lane in p.rules.disabled_lanes:
			p.notes += 1
	p.target_score = RogueCatalog.score_target(boss.index, p.notes)
	return p


static func _apply_consumables(run: RogueRun, p: RoguePrepared) -> void:
	var r := run.rng_for("consumables")
	for id in run.pending:
		var data: Dictionary = RogueCatalog.CONSUMABLE[id]
		match id:
			"cascos_rotos":
				var dirs: Array = Settings.DIRECTION_LANES.duplicate()
				for i in 2:
					var lane: int = dirs.pop_at(r.randi_range(0, dirs.size() - 1))
					p.rules.disabled_lanes.append(lane)
				p.notices.append(Lang.t("Cascos Rotos: %s y %s desactivadas") % [
					Lanes.lane_name(p.rules.disabled_lanes[-2]), Lanes.lane_name(p.rules.disabled_lanes[-1])])
			"ensayo":
				p.rules.risk_free_until_ms = REHEARSAL_MS
				p.notices.append(Lang.t("Ensayo: los primeros 15 s no cuentan"))
			"grabadora":
				p.slot_uses = 2
			"soborno":
				var active := p.boss.active_abilities()
				if not active.is_empty():
					p.boss.bribed = active[r.randi_range(0, active.size() - 1)]
					p.notices.append(Lang.t("Soborno: %s desactivada") % RogueCatalog.ability_name(p.boss.bribed))
			"contrato":
				p.money_mult *= float(data["money_mult"])
				p.rules.miss_limit += int(data["misses"])
			"cuerdas":
				p.rules.miss_limit += int(data["misses"])
		p.consumed.append(id)


static func _apply_arrows(run: RogueRun, p: RoguePrepared) -> void:
	var twins: Array[int] = []
	for lane in run.arrows:
		var id: String = run.arrows[lane]["id"]
		var data: Dictionary = RogueCatalog.ARROW[id]
		match id:
			"dorada":
				p.rules.lane_score_mult[lane] *= float(data["mult"])
			"cristal":
				p.rules.lane_score_mult[lane] *= float(data["mult"])
				p.rules.lane_miss_weight[lane] = 2
			"iman":
				p.rules.lane_window_mult[lane] *= float(data["window"])
			"escudo":
				p.rules.shield_lanes.append(lane)
			"hucha":
				p.rules.lane_score_mult[lane] *= float(data["mult"])
				p.rules.coin_lanes.append(lane)
			"maldita":
				p.rules.lane_score_mult[lane] *= float(data["mult"])
				p.rules.cursed_lanes.append(lane)
			"hielo":
				p.rules.unbreakable_hold_lanes.append(lane)
			"gemela":
				twins.append(lane)
	# Gemela al final: copia el multiplicador ya calculado de su vecina.
	for lane in twins:
		p.rules.lane_score_mult[lane] = p.rules.lane_score_mult[twin_source(lane)]


## La flecha de la que copia una Gemela: la de su izquierda en pantalla, o la
## de su derecha si esta en el borde.
static func twin_source(lane: int) -> int:
	var slot := Lanes.display_index(lane)
	var neighbor := slot - 1 if slot > 0 else slot + 1
	return Lanes.DISPLAY_ORDER[neighbor]


static func _apply_boss(run: RogueRun, p: RoguePrepared) -> void:
	var r := run.rng_for("boss")
	var rules := p.rules
	var length := p.length_ms
	var active := p.boss.active_abilities()

	# Primero lo que mueve notas de carril, luego lo que las marca: asi un Doble
	# Golpe no cae en una nota que luego desaparece.
	var order := ["cuerda_rota", "polirritmia", "carril_minado", "pegajosas"]
	var sorted: Array[String] = []
	for id in order:
		if id in active:
			sorted.append(id)
	for id in active:
		if not id in sorted:
			sorted.append(id)

	for id in sorted:
		var data: Dictionary = RogueCatalog.ABILITY[id]
		match id:
			"inversion":
				var seg := ChartTransforms.random_segment(r, length, RogueCatalog.BOSS_SEGMENT)
				rules.add_effect(TimedEffect.INVERT, seg.x, seg.y)
			"crescendo":
				rules.crescendo_to = float(data["scroll_to"])
			"ondulada":
				rules.wave = true
			"zoom":
				rules.zoom = true
			"ritardando":
				rules.add_effect(TimedEffect.TEMPO, length * 0.5, INF, {"tempo": float(data["tempo"])})
			"doble_golpe":
				ChartTransforms.double_hits(p.chart, r, float(data["fraction"]))
			"impuesto":
				p.tax = float(data["tax"])
			"senuelos":
				ChartTransforms.add_decoys(p.chart, r, float(data["fraction"]))
			"abucheo":
				rules.scroll_per_miss = float(data["scroll_per_miss"])
			"acoplamiento":
				var seg := ChartTransforms.random_segment(r, length, float(data["span"]))
				rules.add_effect(TimedEffect.SLOT_BLOCKED, seg.x, seg.y)
			"pista_invertida":
				var seg := ChartTransforms.random_segment(r, length, RogueCatalog.BOSS_SEGMENT)
				rules.add_effect(TimedEffect.REVERSE, seg.x, seg.y)
			"camufladas":
				rules.camouflage = true
			"silencio":
				var seg := ChartTransforms.random_segment(r, length, float(data["span"]))
				rules.add_effect(TimedEffect.SILENCE, seg.x, seg.y)
			"cuerda_rota":
				var lane := ChartTransforms.break_string(p.chart, r)
				rules.disabled_lanes.append(lane)
				p.notices.append(Lang.t("Cuerda Rota: %s no funciona") % Lanes.lane_name(lane))
			"escudo_jefe":
				rules.boss_shield_perfects = int(data["perfects"])
				rules.boss_shield_regen_ms = float(data["regen_s"]) * 1000.0
			"ventana_estrecha":
				rules.perfect_window_mult = float(data["perfect_mult"])
			"saqueador":
				rules.steal_after_misses = int(data["misses"])
			"carril_minado":
				var seg := ChartTransforms.random_segment(r, length, RogueCatalog.BOSS_SEGMENT)
				var lane := ChartTransforms.minefield(p.chart, seg.x, seg.y)
				if lane != -1:
					p.notices.append(Lang.t("Carril Minado: %s") % Lanes.lane_name(lane))
			"fantasma":
				rules.ghost = true
			"cambio_clave":
				rules.key_rotation_every = int(data["every"])
			"polirritmia":
				var lane := ChartTransforms.polyrhythm(p.chart, r)
				if lane != -1:
					p.notices.append(Lang.t("Polirritmia: %s va en tresillos") % Lanes.lane_name(lane))
			"pegajosas":
				var seg := ChartTransforms.random_segment(r, length, STICKY_SEGMENT)
				ChartTransforms.sticky_notes(p.chart, seg.x, seg.y)
			"maldicion":
				var options: Array[int] = []
				for lane in Settings.DIRECTION_LANES:
					if not lane in rules.cursed_lanes and not lane in rules.disabled_lanes:
						options.append(lane)
				if not options.is_empty():
					var lane := options[r.randi_range(0, options.size() - 1)]
					rules.cursed_lanes.append(lane)
					rules.lane_score_mult[lane] *= float(RogueCatalog.ARROW["maldita"]["mult"])
					p.notices.append(Lang.t("Maldición: %s es Maldita") % Lanes.lane_name(lane))
