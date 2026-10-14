class_name Judgement
extends RefCounted

## Resultado de un intento de hit, sus ventanas y su puntuacion.
##
## Cuanto mas lejos del momento justo, menos puntos. Las ventanas son las de
## Friday Night Funkin' (45 / 90 / 135 / 166 ms), que es la referencia que se
## busca imitar.

enum Kind { PERFECT, GOOD, NORMAL, BAD, MISS }

## Ventanas, en ms de diferencia absoluta entre el toque y la nota.
const PERFECT_MS := 45.0
const GOOD_MS := 90.0
const NORMAL_MS := 135.0
const BAD_MS := 165.0
## Fuera de esto el toque ya no cuenta para la nota: es Errada.
const HIT_WINDOW_MS := BAD_MS

const SCORES := {
	Kind.PERFECT: 350,
	Kind.GOOD: 200,
	Kind.NORMAL: 100,
	Kind.BAD: 50,
	Kind.MISS: -100,
}

## Peso de cada nivel en la precision (%).
const ACCURACY := {
	Kind.PERFECT: 1.0,
	Kind.GOOD: 0.75,
	Kind.NORMAL: 0.5,
	Kind.BAD: 0.25,
	Kind.MISS: 0.0,
}

## Bonus maximo por combo que se suma a cada acierto.
const COMBO_BONUS_CAP := 50

## Fallos permitidos. Al superarlo, se pierde.
const MAX_MISSES := 15

const NAMES := {
	Kind.PERFECT: "Perfecto",
	Kind.GOOD: "Bueno",
	Kind.NORMAL: "Normal",
	Kind.BAD: "Vaya...",
	Kind.MISS: "Errada",
}

const COLORS := {
	Kind.PERFECT: Color("4de8ff"),
	Kind.GOOD: Color("2ee6a8"),
	Kind.NORMAL: Color("ffd23f"),
	Kind.BAD: Color("ff9f43"),
	Kind.MISS: Color("f9393f"),
}

## Orden en que se listan en pantalla (de mejor a peor).
const ORDER: Array[Kind] = [Kind.PERFECT, Kind.GOOD, Kind.NORMAL, Kind.BAD, Kind.MISS]


## Puntos extra por mantener una nota larga hasta el final.
const HOLD_BONUS := 100


## Clasifica una diferencia (toque - nota). Fuera de HIT_WINDOW_MS es MISS.
static func classify(delta_ms: float) -> Kind:
	return classify_with(delta_ms, 1.0, 1.0)


## Igual, con las ventanas escaladas. `perfect_mult` solo afecta a Perfecto
## (Ventana Estrecha); `mult`, a todas (Afinador, Flecha Iman).
static func classify_with(delta_ms: float, mult: float, perfect_mult: float) -> Kind:
	var d := absf(delta_ms)
	if d <= PERFECT_MS * mult * perfect_mult:
		return Kind.PERFECT
	if d <= GOOD_MS * mult:
		return Kind.GOOD
	if d <= NORMAL_MS * mult:
		return Kind.NORMAL
	if d <= BAD_MS * mult:
		return Kind.BAD
	return Kind.MISS


static func score_for(kind: Kind, combo: int) -> int:
	if kind == Kind.MISS:
		return SCORES[kind]
	return SCORES[kind] + mini(combo, COMBO_BONUS_CAP)


## "pronto" / "tarde" para los aciertos que no son perfectos, o "" si no aplica.
## Es lo que le dice al jugador hacia que lado corregir.
static func timing_hint(kind: Kind, delta_ms: float) -> String:
	if kind == Kind.PERFECT or kind == Kind.MISS:
		return ""
	return "pronto" if delta_ms < 0.0 else "tarde"
