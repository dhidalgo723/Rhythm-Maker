class_name AudioLoader
extends RefCounted

## Carga audio desde el sistema de archivos del usuario en runtime.
## load() de Godot solo sirve para recursos importados (res://), asi que hay
## que usar los load_from_file() estaticos de cada AudioStream.

const SUPPORTED := ["wav", "mp3", "ogg"]
static var FILE_FILTERS := PackedStringArray([
	Lang.t("*.wav ; WAV (recomendado: timing exacto)"),
	"*.mp3 ; MP3",
	"*.ogg ; OGG Vorbis",
])


static func load_stream(path: String) -> AudioStream:
	var ext := path.get_extension().to_lower()
	var stream: AudioStream = null
	# Audio que viene con el juego (canciones del roguelike): en un juego
	# exportado el .wav original no esta, solo su version importada, que se
	# carga como recurso.
	if path.begins_with("res://") and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
		ext = ""
	match ext:
		"":
			pass
		"wav":
			stream = AudioStreamWAV.load_from_file(path)
		"mp3":
			stream = AudioStreamMP3.load_from_file(path)
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
		_:
			push_error("Formato no soportado: .%s" % ext)
			return null

	if stream == null:
		push_error("No se pudo decodificar el audio: %s" % path)
		return null

	# El loop arruina el timing del chart (la posicion se reinicia sola).
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false

	return stream


## MP3 puede meter padding del encoder al inicio (jitter/offset en el decode).
## Se avisa para que el usuario sepa por que el sync puede sentirse distinto.
static func is_timing_reliable(path: String) -> bool:
	return path.get_extension().to_lower() != "mp3"
