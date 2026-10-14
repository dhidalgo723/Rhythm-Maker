extends Node

## Autoload: Gui. Todo lo que es comun a la interfaz de todas las escenas:
##   - aplica el tema de pixel art (GuiTheme) a la ventana entera
##   - permite navegar los menus con W/A/S/D ademas de con las flechas
##   - dibuja un cursor (triangulo amarillo de "play") junto al control seleccionado
##   - pasar el raton por un boton lo selecciona, para que raton y teclado
##     siempre senalen lo mismo
##
## Navegar con teclado significa que un boton tiene el foco. Durante la
## partida, la grabacion y la calibracion NO debe haber foco: WASD, flechas y
## espacio son ahi teclas de carril, y un boton con foco se las comeria antes
## de que lleguen al juego. Cada escena lo suelta con release_focus().

## Teclas que se suman a la navegacion de la interfaz. Las flechas ya vienen
## de serie en las acciones ui_* de Godot. Se usan teclas FISICAS, igual que
## los carriles: en un teclado AZERTY la posicion de WASD es ZQSD.
const NAV_KEYS := {
	"ui_up": KEY_W,
	"ui_down": KEY_S,
	"ui_left": KEY_A,
	"ui_right": KEY_D,
}

## Margen entre el cursor y el control al que senala, y cuanto se balancea.
const CURSOR_GAP := 4.0
const CURSOR_BOB_PX := 3.0
const CURSOR_BOB_SPEED := 6.0

var theme: Theme

var _cursor: TextureRect
var _bob := 0.0


func _ready() -> void:
	# Debe seguir funcionando con el arbol en pausa: el menu de pausa se navega
	# con teclado como cualquier otro.
	process_mode = Node.PROCESS_MODE_ALWAYS

	theme = GuiTheme.build()
	# Se fusiona con el tema por defecto del motor en vez de ponerlo en la
	# ventana raiz: el tema solo se hereda a traves de nodos Control/Window, y
	# un Control colgado de un CanvasLayer o de un Node normal se quedaria con
	# el aspecto por defecto de Godot. El tema por defecto aplica a todos.
	ThemeDB.get_default_theme().merge_with(theme)

	add_keyboard_navigation()
	_build_cursor()
	get_tree().node_added.connect(_on_node_added)


## Suma WASD a las acciones ui_*. Idempotente: no duplica si ya estaban.
func add_keyboard_navigation() -> void:
	for action in NAV_KEYS:
		var key: int = NAV_KEYS[action]
		var already := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
				already = true
		if already:
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


## Control que tiene ahora el foco, o null.
func focused() -> Control:
	return get_viewport().gui_get_focus_owner()


func _build_cursor() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100   # por encima de cualquier escena
	add_child(layer)

	_cursor = TextureRect.new()
	_cursor.texture = GuiTheme.piece(GuiTheme.CURSOR, GuiTheme.CURSOR_SCALE)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor.visible = false
	layer.add_child(_cursor)


func _process(delta: float) -> void:
	if _cursor == null or _cursor.texture == null:
		return
	var target := focused()
	var show := target != null and target.is_visible_in_tree() \
		and (target is BaseButton or target is Slider or target is LineEdit)
	_cursor.visible = show
	if not show:
		return

	_bob = fmod(_bob + delta * CURSOR_BOB_SPEED, TAU)
	var rect := target.get_global_rect()
	var size := _cursor.texture.get_size()
	var x := rect.position.x - size.x - CURSOR_GAP + sin(_bob) * CURSOR_BOB_PX
	var y := rect.position.y + (rect.size.y - size.y) * 0.5
	_cursor.position = Vector2(maxf(x, 2.0), y).round()


func _on_node_added(node: Node) -> void:
	if node is BaseButton or node is Slider:
		var control := node as Control
		control.mouse_entered.connect(_focus_on_hover.bind(control))


func _focus_on_hover(control: Control) -> void:
	if not is_instance_valid(control) or control.focus_mode == Control.FOCUS_NONE:
		return
	if control is BaseButton and (control as BaseButton).disabled:
		return
	if control.is_visible_in_tree():
		control.grab_focus()
