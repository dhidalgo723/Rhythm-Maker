extends Node

## Autoload: Music. El tema principal, en bucle mientras se esta en los menus.
## Se pausa en Juego Libre, en el roguelike, en partida, al grabar y al
## calibrar (ahi lo que tiene que sonar es la cancion o el metronomo), y al
## volver a un menu sigue por donde iba.
##
## Sin el archivo (no se sube al repo) no suena nada y no pasa nada.

const PATH := "res://music/main_theme.mp3"
## Escenas en las que suena el tema.
const MENU_SCENES: Array[String] = [
	"res://scenes/main_menu.tscn",
	"res://scenes/settings_scene.tscn",
	"res://scenes/edit_menu.tscn",
]
const VOLUME_DB := -8.0

var _player: AudioStreamPlayer
## Escena en la que se miro por ultima vez si tenia que sonar.
var _scene := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not ResourceLoader.exists(PATH):
		return
	var stream: AudioStream = load(PATH)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = VOLUME_DB
	add_child(_player)


## Mira si ha cambiado la escena; solo entonces decide si suena o se pausa.
func _process(_delta: float) -> void:
	if _player == null:
		return
	var current := get_tree().current_scene
	var path := current.scene_file_path if current != null else ""
	if path == _scene:
		return
	_scene = path
	set_playing(path in MENU_SCENES)


func set_playing(on: bool) -> void:
	if _player == null:
		return
	if on:
		if _player.stream_paused:
			_player.stream_paused = false
		elif not _player.playing:
			_player.play()
	elif _player.playing:
		_player.stream_paused = true


func is_playing() -> bool:
	return _player != null and _player.playing and not _player.stream_paused
