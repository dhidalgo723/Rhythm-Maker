class_name TimedEffect
extends RefCounted

## Un efecto activo durante un tramo de la cancion (en ms de cancion).
## Los crean las mejoras al activarse y los jefes al empezar la cancion.

# --- Juego ---
const ALWAYS_PERFECT := "always_perfect"   ## Metronomo: cualquier toque es Perfecto
const ALWAYS_GOOD := "always_good"         ## Pua de Guitarra: cualquier toque es Bueno
const ANY_KEY_PERFECT := "any_key_perfect" ## Beat Drop: da igual la tecla
const WINDOW_X2 := "window_x2"             ## Afinador: ventana de acierto doble
const SUSTAIN := "sustain"                 ## Pedal de Sustain: las largas no se rompen
const SLOT_BLOCKED := "slot_blocked"       ## Acoplamiento: no se puede usar la ranura
# --- Audio ---
const TEMPO := "tempo"                     ## data.tempo: 0.75 = 25% mas lento
const SILENCE := "silence"                 ## Silencio: se corta la musica
# --- Visual ---
const SCROLL := "scroll"                   ## data.mult: velocidad de caida (x1.5 = mas rapido)
const INVERT := "invert"                   ## Inversion: izquierda y derecha cambian de sitio
const REVERSE := "reverse"                 ## Pista Invertida: las notas suben desde abajo

var id := ""
var start_ms := 0.0
var end_ms := 0.0
var data := {}


func _init(effect_id: String = "", from_ms: float = 0.0, to_ms: float = 0.0, extra: Dictionary = {}) -> void:
	id = effect_id
	start_ms = from_ms
	end_ms = to_ms
	data = extra


func is_active(t_ms: float) -> bool:
	return t_ms >= start_ms and t_ms < end_ms


## 0..1 dentro del tramo (para animaciones de entrada y salida).
func progress(t_ms: float) -> float:
	if end_ms <= start_ms:
		return 1.0
	return clampf((t_ms - start_ms) / (end_ms - start_ms), 0.0, 1.0)
