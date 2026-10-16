class_name RogueCatalog
extends RefCounted

## Todo el contenido del modo roguelike como datos: tamanos de jefe, mejoras,
## consumibles y habilidades. Los numeros para equilibrar estan aqui juntos.

enum Size { SMALL, MEDIUM, BIG, FINAL }

const SIZE_NAMES := {
	Size.SMALL: "Pequeño",
	Size.MEDIUM: "Mediano",
	Size.BIG: "Grande",
	Size.FINAL: "Jefe",
}

## Habilidades que solo tienen sentido en el roguelike (dinero y ranura de
## mejora): no se ofrecen en Juego Libre.
const ROGUE_ONLY_ABILITIES: Array[String] = ["impuesto", "acoplamiento", "saqueador"]

## Jefes cuyas habilidades se ven desde el principio de la partida.
const VISIBLE_SIZES: Array[Size] = [Size.SMALL, Size.MEDIUM]

## Clave de tamano en pool.json.
const SIZE_KEYS := {
	Size.SMALL: "small",
	Size.MEDIUM: "medium",
	Size.BIG: "big",
	Size.FINAL: "boss",
}

## duracion, notas totales, fallos permitidos (antes de la reduccion por ronda)
## y velocidad de caida de las notas.
const SIZE_SPECS := {
	Size.SMALL: {"duration_ms": 30000, "notes": 40, "misses": 5, "speed": "lenta"},
	Size.MEDIUM: {"duration_ms": 60000, "notes": 60, "misses": 20, "speed": "media"},    # 60 por minuto
	Size.BIG: {"duration_ms": 120000, "notes": 180, "misses": 35, "speed": "rapida"},    # 90 por minuto
	Size.FINAL: {"duration_ms": 120000, "notes": 270, "misses": 30, "speed": "rapida"},  # 135 por minuto
}

## Velocidad de caida: cuanto tarda una nota en cruzar la pantalla. En el
## roguelike la marca el jefe, no la preferencia del jugador.
const SPEED_TRAVEL_MS := {"lenta": 1600, "media": 1200, "rapida": 850}
const SPEED_NAMES := {"lenta": "lenta", "media": "media", "rapida": "rápida"}


## "30 s" / "2 min".
static func duration_text(ms: int) -> String:
	return "%d min" % (ms / 60000) if ms % 60000 == 0 else "%d s" % (ms / 1000)


## "30 s, 40 notas, 15 fallos, velocidad lenta": resumen de un tamano.
static func size_summary(size: Size) -> String:
	var spec: Dictionary = SIZE_SPECS[size]
	return Lang.t("%s, %d notas, %d fallos, velocidad %s") % [
		duration_text(int(spec["duration_ms"])), int(spec["notes"]), int(spec["misses"]),
		speed_name(spec["speed"])]


# Nombres y descripciones en el idioma actual. Las tablas de abajo guardan el
# texto en espanol; se traduce aqui, al mostrarlo.

static func size_name(size: Size) -> String:
	return Lang.t(SIZE_NAMES[size])


static func speed_name(speed: String) -> String:
	return Lang.t(SPEED_NAMES[speed])


static func kind_name(kind: ItemKind) -> String:
	return Lang.t(KIND_NAMES[kind])


static func item_name(kind: ItemKind, id: String) -> String:
	return Lang.t(str(item(kind, id).get("name", id)))


static func item_desc(kind: ItemKind, id: String) -> String:
	return Lang.t(str(item(kind, id).get("desc", "")))


static func ability_desc(id: String) -> String:
	return Lang.t(ABILITY[id]["desc"]) if ABILITY.has(id) else ""


static func combo_name(id: String) -> String:
	return Lang.t(FINAL_COMBOS[id]["name"])


## Reglas del modo, una por linea (portada del roguelike y Ajustes > Informacion).
static func rules_lines() -> Array[String]:
	return [
		Lang.t("5 canciones seguidas: Pequeña, Mediana, Mediana, Grande y el Jefe."),
		"",
		Lang.t("• Pequeño: %s.") % size_summary(Size.SMALL),
		Lang.t("• Mediano: %s.") % size_summary(Size.MEDIUM),
		Lang.t("• Grande: %s.") % size_summary(Size.BIG),
		Lang.t("• Jefe: %s.") % size_summary(Size.FINAL),
		Lang.t("• Cada canción tiene una puntuación que alcanzar y un límite de fallos."),
		Lang.t("• Si fallas de más o no llegas a la puntuación, la partida vuelve a empezar desde cero."),
		Lang.t("• Al pasar una canción ganas dinero según los fallos que te sobraron, y entras a la venta de garaje."),
		Lang.t("• Tienes 1 ranura de mejora: se activa con Intro o Shift izquierdo, una vez por canción."),
		Lang.t("• Las habilidades de los jefes pequeños y medianos se ven desde el principio; las de los grandes y el Jefe, al empezar la canción."),
	]


static func travel_ms(size: Size) -> int:
	return SPEED_TRAVEL_MS[SIZE_SPECS[size]["speed"]]

## Las 5 canciones de una partida: Pequeno, Mediano, Mediano, Grande y el Jefe.
const SEQUENCE: Array[Size] = [Size.SMALL, Size.MEDIUM, Size.MEDIUM, Size.BIG, Size.FINAL]

## Puntuacion a alcanzar, como fraccion de la maxima sin combo (notas x 350).
const TARGET_FIRST := 0.40
const TARGET_LAST := 0.66

## Dinero al pasar una cancion: base + bono segun los fallos que sobraron.
const REWARD_BASE := {Size.SMALL: 4, Size.MEDIUM: 5, Size.BIG: 6, Size.FINAL: 0}
const REWARD_BONUS := {Size.SMALL: 4, Size.MEDIUM: 5, Size.BIG: 6, Size.FINAL: 0}

## Las tres cajas de la venta de garaje y la probabilidad de lo que sale en
## cada una (izquierda, centro, derecha).
const SHOP_BOXES := [
	{"consumable": 1.0},
	{"slot": 0.9, "arrow": 0.1},
	{"arrow": 0.7, "slot": 0.3},
]

## Proporcion de la cancion que ocupan las habilidades "de tramo".
const BOSS_SEGMENT := 0.20

# ---------------------------------------------------------------- Ranura
## Se activan con Intro o Shift izquierdo, una vez por cancion. "span" es la
## fraccion de la cancion que dura el efecto.
const SLOT := {
	"pua": {"name": "Púa de Guitarra", "price": 4, "image": "Pua de Guittara.png", "span": 0.05,
		"desc": "Durante un 5% de la canción, cualquier toque puntúa como Bueno."},
	"metronomo": {"name": "Metrónomo", "price": 7, "image": "Metronomo.png", "span": 0.05,
		"desc": "Durante un 5% de la canción, da igual cuándo pulses: siempre Perfecto."},
	"fast_forward": {"name": "Fast Forward", "price": 5, "image": "Fast Forward.png", "span": 0.05,
		"desc": "Adelanta hasta un 5% de la canción."},
	"pausa": {"name": "Pausa", "price": 3, "image": "Pausa.png", "seconds": 3.0,
		"desc": "Pausa la canción durante 3 segundos."},
	"pad_dj": {"name": "Pad de DJ", "price": 5, "image": "Pad de DJ.png", "span": 0.05,
		"desc": "Durante un 5% de la canción, todas las flechas pasan por el espacio."},
	"afinador": {"name": "Afinador", "price": 5, "image": "Afinador.png", "span": 0.07,
		"desc": "Durante un 7% de la canción, la ventana de acierto es el doble de amplia."},
	"casete": {"name": "Cinta de Casete", "price": 7, "image": "Cinta de Casette.png", "span": 0.05,
		"desc": "Rebobina un 5% de la canción y borra los fallos de ese tramo."},
	"sustain": {"name": "Pedal de Sustain", "price": 4, "image": "Pedal de Sustain.png", "span": 0.15,
		"desc": "Durante un 15%, las notas largas cuentan completas aunque sueltes antes."},
	"tocadiscos": {"name": "Tocadiscos", "price": 5, "image": "Tocadiscos.png", "span": 0.10, "tempo": 0.75,
		"desc": "Durante un 10% de la canción, el tempo baja un 25%."},
	"partitura": {"name": "Partitura", "price": 3, "image": "Partitura.png", "span": 0.05, "scroll": 0.6,
		"desc": "Durante un 5%, las notas bajan más despacio (el audio no cambia)."},
	"distorsion": {"name": "Pedal de Distorsión", "price": 6, "image": "Pedal de Distorsion.png", "span": 0.15, "scroll": 1.25,
		"desc": "Si no fallas durante un 15% de la canción, se borran todos sus fallos. A cambio, las notas van x1.25 más rápido."},
	"arreglo": {"name": "Arreglo Simplificado", "price": 4, "image": "Arreglo Simplificado.png", "span": 0.10,
		"desc": "Durante un 10%, los acordes (notas a la vez) se quedan en una sola nota."},
	"bis": {"name": "Bis", "price": 8, "image": "Bis.png", "passive": true,
		"desc": "Si superas el límite de fallos, sobrevives una vez justo en el límite. Se activa solo."},
	"beat_drop": {"name": "Beat Drop", "price": 8, "image": "Beat Drop.png", "seconds": 15.0, "skip_seconds": 5.0,
		"penalty_span": 0.10, "scroll": 1.5,
		"desc": "15 s en los que cualquier tecla es Perfecto; luego salta 5 s de canción. A cambio, después las notas van x1.5 durante un 10%."},
}

# ---------------------------------------------------------------- Flechas
## Se ponen en una flecha (carril) a elegir. "songs" = canciones que dura
## (-1 = toda la partida).
const ARROW := {
	"dorada": {"name": "Flecha Dorada", "price": 5, "color": "ffd23f", "songs": 3, "mult": 1.75,
		"desc": "Durante 3 canciones, esa flecha puntúa x1.75."},
	"cristal": {"name": "Flecha de Cristal", "price": 5, "color": "bff6ff", "songs": -1, "mult": 2.5,
		"desc": "Esa flecha puntúa x2.5, pero cada fallo en ella cuenta doble."},
	"iman": {"name": "Flecha Imán", "price": 4, "color": "f9393f", "songs": -1, "window": 1.5,
		"desc": "La ventana de acierto de esa flecha es x1.5 más amplia."},
	"escudo": {"name": "Flecha Escudo", "price": 4, "color": "8fa8c8", "songs": -1,
		"desc": "El primer fallo de cada canción en esa flecha no cuenta."},
	"hucha": {"name": "Flecha Hucha", "price": 4, "color": "ff9ec7", "songs": -1, "mult": 0.75, "perfects_per_coin": 10,
		"desc": "Cada 10 perfectos en ella dan 1 moneda extra, pero puntúa x0.75."},
	"gemela": {"name": "Flecha Gemela", "price": 5, "color": "b48cff", "songs": -1,
		"desc": "Copia el multiplicador de la flecha de su izquierda."},
	"maldita": {"name": "Flecha Maldita", "price": 6, "color": "6a3b8f", "songs": -1, "mult": 3.0,
		"desc": "Puntúa x3, pero sus notas son invisibles el último tramo antes de la línea."},
	"hielo": {"name": "Flecha de Hielo", "price": 3, "color": "7fd6ff", "songs": -1,
		"desc": "Las notas largas en esa flecha no se rompen aunque sueltes."},
}

# ---------------------------------------------------------------- Consumibles
## Se compran y afectan a la siguiente cancion (salvo Setlist, que es al momento).
const CONSUMABLE := {
	"setlist": {"name": "Setlist", "price": 2, "image": "Setlist.png",
		"desc": "Revela el jefe de la siguiente canción y renueva la tienda una vez."},
	"cascos_rotos": {"name": "Cascos Rotos", "price": 4, "image": "Cascos Rotos.png",
		"desc": "Se desactivan 2 flechas al azar durante 1 canción. Sus notas desaparecen: no te perjudica."},
	"ensayo": {"name": "Ensayo", "price": 3, "image": "Ensayo.png", "seconds": 15.0,
		"desc": "Juegas sin riesgo los primeros 15 s de la siguiente canción."},
	"grabadora": {"name": "Grabadora", "price": 4, "image": "Grabadora.png",
		"desc": "Tu mejora de ranura tiene 2 usos en la siguiente canción."},
	"soborno": {"name": "Soborno al Técnico", "price": 5, "image": "Soborno al Tecnico.png",
		"desc": "Desactiva una habilidad del siguiente jefe."},
	"contrato": {"name": "Contrato Discográfico", "price": 3, "image": "Contrato Discografico.png", "money_mult": 2.0, "misses": -5,
		"desc": "x2 de dinero en la siguiente canción, pero -5 al límite de fallos."},
	"cuerdas": {"name": "Juego de Cuerdas Nuevas", "price": 3, "image": "Juego de Cuerdas Nuevo.png", "misses": 3,
		"desc": "+3 al límite de fallos en la siguiente canción."},
}

# ---------------------------------------------------------------- Jefes
const ABILITY := {
	# --- Pequeños ---
	"inversion": {"name": "Inversión", "size": Size.SMALL,
		"desc": "Los carriles izquierda y derecha se intercambian durante un tramo."},
	"crescendo": {"name": "Crescendo", "size": Size.SMALL, "scroll_to": 1.6,
		"desc": "La velocidad sube poco a poco durante toda la canción."},
	"ondulada": {"name": "Pista Ondulada", "size": Size.SMALL,
		"desc": "La pista se curva y ondula como una serpiente."},
	"zoom": {"name": "Zoom de Cámara", "size": Size.SMALL,
		"desc": "La cámara se acerca y se aleja al ritmo."},
	"ritardando": {"name": "Ritardando", "size": Size.SMALL, "tempo": 0.8,
		"desc": "El tempo baja de golpe a mitad de canción."},
	"doble_golpe": {"name": "Doble Golpe", "size": Size.SMALL, "fraction": 0.15,
		"desc": "Algunas notas hay que pulsarlas 2 veces seguidas."},
	"impuesto": {"name": "Impuesto", "size": Size.SMALL, "tax": 0.025,
		"desc": "El jefe se queda un 2,5% del dinero que ganes en esta canción."},
	# --- Medianos ---
	"senuelos": {"name": "Notas Señuelo", "size": Size.MEDIUM, "fraction": 0.08,
		"desc": "Aparecen notas rojas que no debes pulsar; pulsarlas cuenta como fallo."},
	"abucheo": {"name": "Abucheo", "size": Size.MEDIUM, "scroll_per_miss": 0.05,
		"desc": "Cada fallo aumenta un poco la velocidad."},
	"acoplamiento": {"name": "Acoplamiento", "size": Size.MEDIUM, "span": 0.20,
		"desc": "Bloquea la ranura de mejora durante un 20% de la canción."},
	"pista_invertida": {"name": "Pista Invertida", "size": Size.MEDIUM,
		"desc": "Las notas suben desde abajo durante un tramo de la canción."},
	"camufladas": {"name": "Notas Camufladas", "size": Size.MEDIUM,
		"desc": "Todas las notas se vuelven del mismo color y sin icono de dirección."},
	"silencio": {"name": "Silencio", "size": Size.MEDIUM, "span": 0.15,
		"desc": "La música se corta durante un tramo: sigue tocando con lo que ves."},
	"cuerda_rota": {"name": "Cuerda Rota", "size": Size.MEDIUM,
		"desc": "Un carril deja de funcionar y sus notas se reparten entre los otros."},
	"escudo_jefe": {"name": "Escudo del Jefe", "size": Size.MEDIUM, "perfects": 5, "regen_s": 20.0,
		"desc": "No puntúas hasta acertar 5 perfectos seguidos; luego el escudo se regenera."},
	"ventana_estrecha": {"name": "Ventana Estrecha", "size": Size.MEDIUM, "perfect_mult": 0.5,
		"desc": "La ventana de Perfecto se reduce a la mitad."},
	"saqueador": {"name": "Saqueador", "size": Size.MEDIUM, "misses": 5,
		"desc": "Si fallas 5 notas seguidas, te roba la mejora de la ranura."},
	# --- Grandes ---
	"carril_minado": {"name": "Carril Minado", "size": Size.BIG,
		"desc": "Una flecha pasa a tener solo señuelos durante un tramo."},
	"fantasma": {"name": "Notas Fantasma", "size": Size.BIG,
		"desc": "Las notas desaparecen justo antes de llegar a la línea."},
	"polirritmia": {"name": "Polirritmia", "size": Size.BIG,
		"desc": "Un carril sigue tresillos mientras los demás van en negras o corcheas."},
	"pegajosas": {"name": "Notas Pegajosas", "size": Size.BIG,
		"desc": "En un tramo aparecen muchas notas largas que hay que mantener mientras tocas otras."},
	"maldicion": {"name": "Maldición", "size": Size.BIG,
		"desc": "Convierte una de tus flechas en Maldita durante esta canción."},
	"teclas_mezcladas": {"name": "Teclas Mezcladas", "size": Size.BIG,
		"desc": "En un tramo de la canción las flechas caen por cualquier carril: pulsa la tecla de la flecha, no la del carril por el que cae."},
	"rasgueo": {"name": "Rasgueo", "size": Size.BIG, "min_ms": 450, "gap_ms": 120,
		"desc": "Las notas largas se parten en 2 o 3 trozos con un pequeño hueco entre ellos."},
}

## Jefe final: una combinacion fija de habilidades.
const FINAL_COMBOS := {
	"techno": {"name": "Techno", "abilities": ["carril_minado", "cuerda_rota", "ventana_estrecha"]},
	"mainstream": {"name": "Mainstream", "abilities": ["saqueador", "abucheo", "pegajosas"]},
	"metal": {"name": "Metal", "abilities": ["maldicion", "fantasma", "doble_golpe"]},
	"rap": {"name": "Rap", "abilities": ["ventana_estrecha", "teclas_mezcladas", "silencio"]},
	"rock": {"name": "Rock", "abilities": ["polirritmia", "pista_invertida", "teclas_mezcladas"]},
	"salsa": {"name": "Salsa", "abilities": ["acoplamiento", "zoom", "crescendo", "doble_golpe"]},
	"experimental": {"name": "Experimental", "abilities": ["polirritmia", "teclas_mezcladas"]},
}

enum ItemKind { SLOT, ARROW, CONSUMABLE }

const KIND_NAMES := {
	ItemKind.SLOT: "Mejora de ranura",
	ItemKind.ARROW: "Mejora de flecha",
	ItemKind.CONSUMABLE: "Consumible",
}


static func table(kind: ItemKind) -> Dictionary:
	match kind:
		ItemKind.SLOT:
			return SLOT
		ItemKind.ARROW:
			return ARROW
		_:
			return CONSUMABLE


static func item(kind: ItemKind, id: String) -> Dictionary:
	return table(kind).get(id, {})


static func abilities_of_size(size: Size) -> Array[String]:
	var out: Array[String] = []
	for id in ABILITY:
		if ABILITY[id]["size"] == size:
			out.append(id)
	return out


static func ability_name(id: String) -> String:
	return Lang.t(ABILITY[id]["name"]) if ABILITY.has(id) else id


## Fallos permitidos en la cancion `index`, antes de consumibles: los de su
## tamano.
static func miss_limit(index: int) -> int:
	return int(SIZE_SPECS[SEQUENCE[index]]["misses"])


## Puntuacion objetivo de la cancion `index` con `notes` notas reales.
static func score_target(index: int, notes: int) -> int:
	var ratio := lerpf(TARGET_FIRST, TARGET_LAST, float(index) / float(SEQUENCE.size() - 1))
	return roundi(notes * Judgement.SCORES[Judgement.Kind.PERFECT] * ratio)
