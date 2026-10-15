class_name RogueHud
extends Control

## Informacion del roguelike durante la cancion, en la franja libre a la
## derecha de los carriles: jefe, objetivo, ranura, efectos y avisos.

const COLUMN_W := 262.0
const NOTICE_S := 2.4

## Nombre visible de cada efecto activo.
const EFFECT_NAMES := {
	TimedEffect.ALWAYS_GOOD: "Púa de Guitarra",
	TimedEffect.ALWAYS_PERFECT: "Metrónomo",
	TimedEffect.ANY_KEY_PERFECT: "Beat Drop",
	TimedEffect.WINDOW_X2: "Afinador",
	TimedEffect.SUSTAIN: "Pedal de Sustain",
	TimedEffect.SLOT_BLOCKED: "Acoplamiento",
	TimedEffect.TEMPO: "Tempo",
	TimedEffect.SILENCE: "Silencio",
	TimedEffect.SCROLL: "Velocidad",
	TimedEffect.INVERT: "Inversión",
	TimedEffect.REVERSE: "Pista Invertida",
}

var runtime: RogueRuntime
var prepared: RoguePrepared
var pm: PlaybackManager

var _boss_label: Label
var _target_label: Label
var _target_bar: ProgressBar
var _slot_label: Label
var _slot_hint: Label
var _effects_label: Label
var _abilities_label: Label
var _notice_label: Label
var _notice_left := 0.0


func setup(rt: RogueRuntime, prep: RoguePrepared, manager: PlaybackManager) -> void:
	runtime = rt
	prepared = prep
	pm = manager
	rt.notice.connect(show_notice)
	manager.message.connect(show_notice)
	rt.slot_changed.connect(_refresh_slot)
	_build()
	_refresh_slot()


func _build() -> void:
	# Anclas Y margenes: este nodo ya esta en el arbol, y set_anchors_preset a
	# secas conservaria su tamano actual (0x0) en vez de ocupar la pantalla.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	col.offset_left = -COLUMN_W - 8
	col.offset_right = -8
	col.offset_top = 84
	col.offset_bottom = -40
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	_boss_label = _label(prepared.boss.title(), 18, GuiTheme.TEXT_FOCUS)
	col.add_child(_boss_label)
	col.add_child(_label(Lang.t("Canción %d de %d") % [prepared.boss.index + 1, RogueCatalog.SEQUENCE.size()],
		13, GuiTheme.TEXT_DIM))

	col.add_child(_spacer(6))
	_target_label = _label("", 15, GuiTheme.TEXT)
	col.add_child(_target_label)
	_target_bar = ProgressBar.new()
	_target_bar.show_percentage = false
	_target_bar.custom_minimum_size = Vector2(0, 24)
	_target_bar.max_value = maxi(1, prepared.target_score)
	col.add_child(_target_bar)

	col.add_child(_spacer(6))
	_slot_label = _label("", 15, GuiTheme.TEXT)
	col.add_child(_slot_label)
	_slot_hint = _label("", 12, GuiTheme.TEXT_DIM)
	col.add_child(_slot_hint)

	col.add_child(_spacer(6))
	_effects_label = _label("", 14, Color("4de8ff"))
	col.add_child(_effects_label)

	col.add_child(_spacer(6))
	var abilities: Array[String] = []
	for id in prepared.boss.active_abilities():
		abilities.append("• " + RogueCatalog.ability_name(id))
	if prepared.boss.bribed != "":
		abilities.append(Lang.t("• %s (sobornada)") % RogueCatalog.ability_name(prepared.boss.bribed))
	_abilities_label = _label(Lang.t("Habilidades del jefe:\n") + "\n".join(abilities), 13, Color("ff9f43"))
	col.add_child(_abilities_label)

	# Avisos: centrados sobre los carriles, arriba.
	_notice_label = _label("", 24, GuiTheme.TEXT_FOCUS)
	_notice_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice_label.offset_left = -300
	_notice_label.offset_right = 300
	_notice_label.offset_top = 96
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_notice_label)


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func show_notice(text: String) -> void:
	_notice_label.text = text
	_notice_label.modulate.a = 1.0
	_notice_left = NOTICE_S


func _refresh_slot() -> void:
	if runtime == null:
		return
	var run := runtime.run
	if run.slot_id == "":
		_slot_label.text = Lang.t("Ranura: vacía")
		_slot_hint.text = ""
	elif RogueRuntime._is_passive(run.slot_id):
		_slot_label.text = Lang.t("Ranura: %s") % runtime.slot_name()
		_slot_hint.text = Lang.t("Se activa solo")
	else:
		_slot_label.text = Lang.t("Ranura: %s") % runtime.slot_name()
		_slot_hint.text = Lang.t("Intro o Shift izq. — %d uso(s)") % runtime.uses_left


func _process(delta: float) -> void:
	if pm == null:
		return
	_target_label.text = Lang.t("Objetivo: %d / %d") % [pm.score, prepared.target_score]
	_target_bar.value = mini(pm.score, prepared.target_score)

	var t := pm.get_time_ms()
	var lines: Array[String] = []
	if runtime.pause_seconds_left() > 0.0:
		lines.append(Lang.t("Pausa: %.1f s") % runtime.pause_seconds_left())
	for e in pm.rules.effects:
		if not e.is_active(t) or not EFFECT_NAMES.has(e.id):
			continue
		var left := (e.end_ms - t) / 1000.0
		var effect_name := Lang.t(EFFECT_NAMES[e.id])
		lines.append(effect_name if is_inf(left) else "%s %.0f s" % [effect_name, left])
	if pm.boss_shield_up():
		lines.append(Lang.t("Escudo del jefe activo"))
	_effects_label.text = "\n".join(lines)
	if runtime.run.slot_id != "" and not RogueRuntime._is_passive(runtime.run.slot_id):
		_slot_hint.text = Lang.t("¡Bloqueada!") if runtime.slot_blocked() \
			else Lang.t("Intro o Shift izq. — %d uso(s)") % runtime.uses_left

	if _notice_left > 0.0:
		_notice_left -= delta
		_notice_label.modulate.a = clampf(_notice_left / 0.5, 0.0, 1.0)
