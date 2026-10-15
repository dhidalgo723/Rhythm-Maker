class_name Lang
extends RefCounted

## Idiomas del juego. Los textos se escriben en espanol en el codigo y
## Lang.t() los devuelve en el idioma elegido en Ajustes. Las traducciones al
## ingles estan en LangEn.TEXT, con el texto en espanol como clave: un texto
## sin traduccion sale tal cual, en espanol (lo comprueba tests/smoke_lang).
##
## Para que el espanol no se traduzca solo, el idioma de reserva del proyecto
## es "es" (internationalization/locale/fallback en project.godot).

const CODES: Array[String] = ["es", "en"]
const NAMES := {"es": "Español", "en": "English"}

static var _registered := false


## El texto en el idioma actual.
static func t(text: String) -> String:
	return String(TranslationServer.translate(text))


## Idioma la primera vez que se abre el juego: espanol si el sistema esta en
## espanol, ingles si no.
static func system_default() -> String:
	return "es" if OS.get_locale_language() == "es" else "en"


static func apply(code: String) -> void:
	if not _registered:
		var en := Translation.new()
		en.locale = "en"
		for key in LangEn.TEXT:
			en.add_message(key, LangEn.TEXT[key])
		TranslationServer.add_translation(en)
		_registered = true
	TranslationServer.set_locale(code)


## Entero con separador de miles: 5120 -> "5.120" en espanol, "5,120" en ingles.
static func number(n: int) -> String:
	var digits := str(absi(n))
	var sep := "." if _spanish() else ","
	var out := ""
	while digits.length() > 3:
		out = sep + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## Decimal con la coma o el punto que toca: 94.3 -> "94,3" / "94.3".
static func decimal(value: float, decimals: int = 1) -> String:
	var text := String.num(value, decimals)
	if decimals > 0 and not "." in text:
		text += "." + "0".repeat(decimals)
	return text.replace(".", ",") if _spanish() else text


static func _spanish() -> bool:
	return TranslationServer.get_locale().begins_with("es")
