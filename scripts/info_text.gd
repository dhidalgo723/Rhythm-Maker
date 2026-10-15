class_name InfoText
extends RefCounted

## Textos de Ajustes > Informacion: puntuacion, reglas del roguelike, jefes,
## mejoras y consumibles. Se sacan del catalogo (RogueCatalog, Judgement), asi
## que al cambiar un numero o anadir una mejora la informacion sigue al dia.
## Devuelven BBCode para un RichTextLabel.

const CATEGORIES: Array[String] = [
	"scoring", "rogue_rules",
	"boss_small", "boss_medium", "boss_big", "boss_final",
	"slot", "arrow", "consumable",
]

const TITLES := {
	"scoring": "Puntuación",
	"rogue_rules": "Reglas del roguelike",
	"boss_small": "Jefes pequeños",
	"boss_medium": "Jefes medianos",
	"boss_big": "Jefes grandes",
	"boss_final": "Jefe final",
	"slot": "Mejoras de ranura",
	"arrow": "Mejoras de flecha",
	"consumable": "Consumibles",
}


static func title(category: String) -> String:
	return Lang.t(TITLES[category])


static func text(category: String) -> String:
	match category:
		"scoring":
			return _scoring()
		"rogue_rules":
			return "\n".join(RogueCatalog.rules_lines())
		"boss_small":
			return _abilities(RogueCatalog.Size.SMALL)
		"boss_medium":
			return _abilities(RogueCatalog.Size.MEDIUM)
		"boss_big":
			return _abilities(RogueCatalog.Size.BIG)
		"boss_final":
			return _final_combos()
		"slot":
			return _items(RogueCatalog.ItemKind.SLOT)
		"arrow":
			return _items(RogueCatalog.ItemKind.ARROW)
		_:
			return _items(RogueCatalog.ItemKind.CONSUMABLE)


static func _scoring() -> String:
	var windows := {
		Judgement.Kind.PERFECT: Judgement.PERFECT_MS,
		Judgement.Kind.GOOD: Judgement.GOOD_MS,
		Judgement.Kind.NORMAL: Judgement.NORMAL_MS,
		Judgement.Kind.BAD: Judgement.BAD_MS,
	}
	var lines: Array[String] = [Lang.t("Cuanto más cerca del momento justo toques, más puntos:"), ""]
	for kind in windows:
		lines.append("[color=#%s]%s[/color]   ±%d ms   %s" % [
			Judgement.COLORS[kind].to_html(false), Judgement.label(kind), int(windows[kind]),
			Lang.t("%d puntos") % Judgement.SCORES[kind]])
	lines.append("[color=#%s]%s[/color]   %s" % [
		Judgement.COLORS[Judgement.Kind.MISS].to_html(false), Judgement.label(Judgement.Kind.MISS),
		Lang.t("%d puntos") % Judgement.SCORES[Judgement.Kind.MISS]])
	lines.append("")
	lines.append(Lang.t("• Cada acierto suma hasta %d puntos extra según el combo.") % Judgement.COMBO_BONUS_CAP)
	lines.append(Lang.t("• Debajo del juicio se avisa si tocaste pronto o tarde."))
	lines.append(Lang.t("• En el Modo Juego pierdes al superar %d fallos.") % Judgement.MAX_MISSES)
	lines.append(Lang.t("• Las notas largas hay que mantenerlas pulsadas hasta el final."))
	return "\n".join(lines)


static func _abilities(size: RogueCatalog.Size) -> String:
	var blocks: Array[String] = []
	for id in RogueCatalog.abilities_of_size(size):
		blocks.append(_entry(RogueCatalog.ability_name(id), "", RogueCatalog.ability_desc(id)))
	var visible := Lang.t("Se ven desde el principio de la partida.") if size in RogueCatalog.VISIBLE_SIZES \
		else Lang.t("Ocultas hasta que empieza la canción (o con un Setlist).")
	return "[color=#%s]%s[/color]\n\n%s" % [GuiTheme.TEXT_DIM.to_html(false), visible, "\n\n".join(blocks)]


static func _final_combos() -> String:
	var blocks: Array[String] = [
		"[color=#%s]%s[/color]" % [GuiTheme.TEXT_DIM.to_html(false),
			Lang.t("El último jefe trae una de estas combinaciones de habilidades.")],
	]
	for id in RogueCatalog.FINAL_COMBOS:
		var names: Array[String] = []
		for ability in RogueCatalog.FINAL_COMBOS[id]["abilities"]:
			names.append(RogueCatalog.ability_name(ability))
		blocks.append(_entry(RogueCatalog.combo_name(id), "", ", ".join(names)))
	return "\n\n".join(blocks)


static func _items(kind: RogueCatalog.ItemKind) -> String:
	var blocks: Array[String] = []
	for id in RogueCatalog.table(kind):
		var price := Lang.t("%d monedas") % int(RogueCatalog.item(kind, id)["price"])
		blocks.append(_entry(RogueCatalog.item_name(kind, id), price, RogueCatalog.item_desc(kind, id)))
	return "\n\n".join(blocks)


## Nombre en amarillo, un dato al lado en gris y la descripcion debajo.
static func _entry(entry_name: String, extra: String, desc: String) -> String:
	var head := "[color=#%s]%s[/color]" % [GuiTheme.TEXT_FOCUS.to_html(false), entry_name]
	if extra != "":
		head += "   [color=#%s]%s[/color]" % [GuiTheme.TEXT_DIM.to_html(false), extra]
	return head + "\n" + desc
