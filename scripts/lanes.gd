class_name Lanes
extends RefCounted

const COUNT := 4

## Indice = lane. 0=izq, 1=abajo, 2=arriba, 3=derecha
const ACTIONS: Array[String] = ["lane_0", "lane_1", "lane_2", "lane_3"]
const ARROWS: Array[String] = ["<", "v", "^", ">"]
const COLORS: Array[Color] = [
	Color("c24b99"),  # izq   - magenta
	Color("00ffff"),  # abajo - cyan
	Color("12fa05"),  # arriba- verde
	Color("f9393f"),  # der   - rojo
]


## Devuelve el lane pulsado por este evento, o -1.
## Ignora echo (auto-repeat) para no generar notas fantasma.
static func lane_pressed(event: InputEvent) -> int:
	if event is InputEventKey and (event as InputEventKey).echo:
		return -1
	for i in COUNT:
		if event.is_action_pressed(ACTIONS[i]):
			return i
	return -1


static func lane_released(event: InputEvent) -> int:
	for i in COUNT:
		if event.is_action_released(ACTIONS[i]):
			return i
	return -1
