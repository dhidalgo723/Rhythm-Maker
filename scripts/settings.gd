extends Node

## Autoload: Settings. Preferencias persistentes del usuario.

const CONFIG_PATH := "user://settings.cfg"

## Offset de calibracion, en ms.
## Positivo = los inputs del usuario llegan TARDE respecto al audio que oye.
## Se resta al timestamp del input, tanto al grabar como al juzgar hits.
var offset_ms := 0

## Cuanto tarda una nota en cruzar la pantalla, en ms (scroll speed).
var travel_time_ms := 1200

var last_audio_dir := "user://"


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	offset_ms = int(cfg.get_value("timing", "offset_ms", offset_ms))
	travel_time_ms = int(cfg.get_value("gameplay", "travel_time_ms", travel_time_ms))
	last_audio_dir = str(cfg.get_value("paths", "last_audio_dir", last_audio_dir))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("timing", "offset_ms", offset_ms)
	cfg.set_value("gameplay", "travel_time_ms", travel_time_ms)
	cfg.set_value("paths", "last_audio_dir", last_audio_dir)
	cfg.save(CONFIG_PATH)
