class_name Judgement
extends RefCounted

## Resultado de un intento de hit y sus ventanas/puntajes.

enum Kind { PERFECT, GOOD, MISS }

## Ventanas de tolerancia, en ms de diferencia absoluta.
const PERFECT_MS := 50.0
const GOOD_MS := 100.0

const SCORE_PERFECT := 300
const SCORE_GOOD := 150
const SCORE_MISS := -100

## Bonus maximo por combo que se suma a cada hit.
const COMBO_BONUS_CAP := 50

## Fallos permitidos. Al superarlo, se pierde.
const MAX_MISSES := 15

const NAMES := {
	Kind.PERFECT: "PERFECT",
	Kind.GOOD: "GOOD",
	Kind.MISS: "MISS",
}

const COLORS := {
	Kind.PERFECT: Color("2ee6a8"),
	Kind.GOOD: Color("ffd23f"),
	Kind.MISS: Color("f9393f"),
}


## Clasifica una diferencia (input - nota). Devuelve MISS si cae fuera de GOOD.
static func classify(delta_ms: float) -> Kind:
	var d := absf(delta_ms)
	if d <= PERFECT_MS:
		return Kind.PERFECT
	if d <= GOOD_MS:
		return Kind.GOOD
	return Kind.MISS


static func score_for(kind: Kind, combo: int) -> int:
	match kind:
		Kind.PERFECT:
			return SCORE_PERFECT + mini(combo, COMBO_BONUS_CAP)
		Kind.GOOD:
			return SCORE_GOOD + mini(combo, COMBO_BONUS_CAP)
		_:
			return SCORE_MISS
