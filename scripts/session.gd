extends Node

## Autoload: Session. Estado compartido entre escenas.

# --- Modo edicion: audio elegido por el usuario ---
var audio_path := ""
var audio_stream: AudioStream = null
## Titulo con el que se guardara la grabacion.
var recording_title := ""

# --- Juego Libre: grabacion elegida de la biblioteca ---
var selected_song: SongEntry = null
## Habilidades de jefe que el jugador ha puesto a la cancion (vacio = ninguna).
## Se quedan para Reintentar y como seleccion inicial la proxima vez.
var free_abilities: Array[String] = []

# --- Modo roguelike ---
## Partida en curso (null si no hay ninguna).
var rogue_run: RogueRun = null
## Cancion del roguelike preparada para la escena de juego (null = modo normal).
var rogue_prepared: RoguePrepared = null


func has_audio() -> bool:
	return audio_stream != null


func set_audio(path: String) -> bool:
	var stream := AudioLoader.load_stream(path)
	if stream == null:
		return false
	audio_path = path
	audio_stream = stream
	Settings.last_audio_dir = path.get_base_dir()
	Settings.save_settings()
	return true


func clear_audio() -> void:
	audio_path = ""
	audio_stream = null


## Titulo por defecto de la grabacion: el nombre del archivo sin extension.
func song_title() -> String:
	return audio_path.get_file().get_basename()


func song_name() -> String:
	return audio_path.get_file()
