class_name PlayRules
extends RefCounted

## Reglas de una partida. Los valores por defecto son el juego normal; el modo
## roguelike los cambia segun el jefe, las flechas mejoradas y los consumibles.
##
## PlaybackManager las consulta al juzgar; PlayField, al dibujar. Asi ninguno de
## los dos tiene que saber nada de jefes ni de tiendas.

var miss_limit := Judgement.MAX_MISSES
## Tiempo que tarda una nota en cruzar la pantalla. 0 = el de los Ajustes del
## jugador; el roguelike lo fija segun el tamano del jefe.
var travel_time_ms := 0

# --- Por carril (indice = id de carril) ---
var lane_score_mult := PackedFloat32Array()   ## Dorada x1.75, Cristal x2.5, Hucha x0.75...
var lane_miss_weight := PackedInt32Array()    ## Cristal: cada fallo cuenta 2
var lane_window_mult := PackedFloat32Array()  ## Iman: ventana x1.5
var shield_lanes: Array[int] = []             ## Escudo: el primer fallo no cuenta
var unbreakable_hold_lanes: Array[int] = []   ## Hielo: las largas no se rompen
var coin_lanes: Array[int] = []               ## Hucha: los perfectos dan monedas
var cursed_lanes: Array[int] = []             ## Maldita: invisibles al final del recorrido
var disabled_lanes: Array[int] = []           ## Cascos Rotos / Cuerda Rota: sin notas

# --- Ventanas ---
var perfect_window_mult := 1.0                ## Ventana Estrecha: x0.5

# --- Riesgo ---
var risk_free_until_ms := 0.0                 ## Ensayo: los fallos antes de esto no cuentan
var bis := false                              ## Bis: sobrevives una vez al limite

# --- Jefes ---
var boss_shield_perfects := 0                 ## Escudo del Jefe: perfectos seguidos para romperlo
var boss_shield_regen_ms := 20000.0
var key_rotation_every := 0                   ## Cambio de Clave: cada cuantas notas rota
var steal_after_misses := 0                   ## Saqueador: fallos seguidos para robar
var scroll_per_miss := 0.0                    ## Abucheo: velocidad extra por fallo
var crescendo_to := 1.0                       ## Crescendo: velocidad al final de la cancion

# --- Visuales de toda la cancion ---
var wave := false                             ## Pista Ondulada
var zoom := false                             ## Zoom de Camara
var camouflage := false                       ## Notas Camufladas
var ghost := false                            ## Notas Fantasma

## Tramos con efecto (ver TimedEffect).
var effects: Array[TimedEffect] = []


func _init() -> void:
	lane_score_mult.resize(Lanes.COUNT)
	lane_score_mult.fill(1.0)
	lane_miss_weight.resize(Lanes.COUNT)
	lane_miss_weight.fill(1)
	lane_window_mult.resize(Lanes.COUNT)
	lane_window_mult.fill(1.0)


func add_effect(id: String, from_ms: float, to_ms: float, data: Dictionary = {}) -> TimedEffect:
	var e := TimedEffect.new(id, from_ms, to_ms, data)
	effects.append(e)
	return e
