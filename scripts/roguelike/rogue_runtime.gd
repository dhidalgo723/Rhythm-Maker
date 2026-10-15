class_name RogueRuntime
extends Node

## La parte del roguelike que vive durante la cancion: activar la mejora de la
## ranura (Intro o Shift izquierdo) y lo que pasa con el tiempo (la Pausa de
## 3 s, comprobar el Pedal de Distorsion, el salto del Beat Drop, el robo del
## Saqueador...). Las reglas fijas ya vienen en el PlayRules del RoguePrepared.

const ACTION := "use_upgrade"

signal notice(text: String)
signal slot_changed()

var run: RogueRun
var prepared: RoguePrepared
var pm: PlaybackManager
var uses_left := 0

## Comprobaciones pendientes: {"type": "distortion"|"beat_drop", ...}.
var _checks: Array[Dictionary] = []
var _pause_left := 0.0


func setup(rogue_run: RogueRun, prep: RoguePrepared, manager: PlaybackManager) -> void:
	run = rogue_run
	prepared = prep
	pm = manager
	uses_left = prep.slot_uses if run.slot_id != "" and not _is_passive(run.slot_id) else 0
	pm.slot_stolen.connect(_on_slot_stolen)
	pm.bis_triggered.connect(_on_bis)


func slot_name() -> String:
	return RogueCatalog.item_name(RogueCatalog.ItemKind.SLOT, run.slot_id) if run.slot_id != "" else ""


func slot_blocked() -> bool:
	return pm.is_effect_active(TimedEffect.SLOT_BLOCKED, pm.get_time_ms())


static func _is_passive(id: String) -> bool:
	return bool(RogueCatalog.SLOT.get(id, {}).get("passive", false))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		get_viewport().set_input_as_handled()
		var why := activate()
		if why != "":
			notice.emit(why)


## Gasta un uso de la mejora de la ranura. Devuelve "" o por que no se pudo.
func activate() -> String:
	if pm == null or not pm.is_active() or pm.clock.is_paused():
		return Lang.t("Ahora no")
	if run.slot_id == "":
		return Lang.t("No tienes mejora en la ranura")
	if _is_passive(run.slot_id):
		return Lang.t("%s se activa solo") % slot_name()
	if uses_left <= 0:
		return Lang.t("Ya usaste %s en esta canción") % slot_name()
	if slot_blocked():
		return Lang.t("¡Acoplamiento! La ranura está bloqueada")

	var id := run.slot_id
	var data: Dictionary = RogueCatalog.SLOT[id]
	var t := pm.get_time_ms()
	var span := prepared.length_ms * float(data.get("span", 0.0))
	match id:
		"pua":
			pm.add_effect(TimedEffect.ALWAYS_GOOD, t, t + span)
		"metronomo":
			pm.add_effect(TimedEffect.ALWAYS_PERFECT, t, t + span)
		"fast_forward":
			pm.skip(span)
		"pausa":
			_pause_left = float(data["seconds"])
			pm.clock.set_paused(true)
		"pad_dj":
			pm.move_notes_to_lane(t, t + span, Lanes.SPACE)
		"afinador":
			pm.add_effect(TimedEffect.WINDOW_X2, t, t + span)
		"casete":
			var erased := pm.rewind(span)
			notice.emit(Lang.t("Rebobinado: %d fallo(s) borrado(s)") % erased)
		"sustain":
			pm.add_effect(TimedEffect.SUSTAIN, t, t + span)
		"tocadiscos":
			pm.add_effect(TimedEffect.TEMPO, t, t + span, {"tempo": float(data["tempo"])})
		"partitura":
			pm.add_effect(TimedEffect.SCROLL, t, t + span, {"mult": float(data["scroll"])})
		"distorsion":
			pm.add_effect(TimedEffect.SCROLL, t, t + span, {"mult": float(data["scroll"])})
			_checks.append({"type": "distortion", "from": t, "to": t + span})
		"arreglo":
			var removed := simplify_chords(t, t + span)
			notice.emit(Lang.t("Arreglo: %d nota(s) de acorde quitada(s)") % removed)
		"beat_drop":
			var drop_ms := float(data["seconds"]) * 1000.0
			pm.add_effect(TimedEffect.ANY_KEY_PERFECT, t, t + drop_ms)
			_checks.append({"type": "beat_drop", "at": t + drop_ms})

	uses_left -= 1
	notice.emit(Lang.t("¡%s!") % slot_name())
	slot_changed.emit()
	return ""


## Arreglo Simplificado: de cada grupo de notas a la vez se queda una (la mas
## a la izquierda en pantalla).
func simplify_chords(from_ms: float, to_ms: float) -> int:
	var groups := {}
	for lane in Lanes.DISPLAY_ORDER:
		for pn: PlayNote in pm.lane_notes(lane):
			if pn.state != PlayNote.State.PENDING or pn.note.decoy:
				continue
			if pn.time_ms < from_ms or pn.time_ms >= to_ms:
				continue
			var key := roundi(pn.time_ms / float(ChartTransforms.SAME_TIME_MS))
			if not groups.has(key):
				groups[key] = []
			groups[key].append(pn)
	var extra := {}
	for key in groups:
		var group: Array = groups[key]
		for i in range(1, group.size()):
			extra[group[i]] = true
	return pm.skip_notes(from_ms, to_ms, func(pn: PlayNote) -> bool: return extra.has(pn))


func _process(delta: float) -> void:
	if pm == null or not pm.is_active():
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		if _pause_left <= 0.0:
			pm.clock.set_paused(false)
			notice.emit(Lang.t("¡Sigue!"))
		return

	var t := pm.get_time_ms()
	for check in _checks.duplicate():
		match check["type"]:
			"distortion":
				if t >= float(check["to"]):
					_checks.erase(check)
					_resolve_distortion(float(check["from"]), float(check["to"]))
			"beat_drop":
				if t >= float(check["at"]):
					_checks.erase(check)
					_finish_beat_drop()


func pause_seconds_left() -> float:
	return maxf(_pause_left, 0.0)


## Pedal de Distorsion: si no hubo fallos en su tramo, se borran todos los de
## la cancion.
func _resolve_distortion(from_ms: float, to_ms: float) -> void:
	for entry in pm.miss_log:
		var t := float(entry["t"])
		if t >= from_ms and t < to_ms:
			notice.emit(Lang.t("Distorsión: fallaste en el tramo"))
			return
	var erased := pm.erase_all_misses()
	notice.emit(Lang.t("¡Distorsión! %d fallo(s) borrado(s)") % erased)


## Beat Drop: salta 5 s y luego las notas van x1.5 durante un 10%.
func _finish_beat_drop() -> void:
	var data: Dictionary = RogueCatalog.SLOT["beat_drop"]
	pm.skip(float(data["skip_seconds"]) * 1000.0)
	var t := pm.get_time_ms()
	var span := prepared.length_ms * float(data["penalty_span"])
	pm.add_effect(TimedEffect.SCROLL, t, t + span, {"mult": float(data["scroll"])})
	notice.emit(Lang.t("¡Drop! Las notas van más rápido"))


func _on_slot_stolen() -> void:
	if run.slot_id == "":
		return
	var lost := slot_name()
	run.slot_id = ""
	uses_left = 0
	notice.emit(Lang.t("¡El Saqueador te ha robado %s!") % lost)
	slot_changed.emit()


## Bis se gasta al salvarte.
func _on_bis() -> void:
	run.slot_id = ""
	uses_left = 0
	slot_changed.emit()
