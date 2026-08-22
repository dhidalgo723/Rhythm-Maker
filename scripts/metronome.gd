class_name Metronome
extends RefCounted

## Genera una pista de metronomo por codigo, para no depender de un asset.
##
## Se genera como pista de audio de verdad (y no como clicks disparados desde
## _process) a proposito: asi el metronomo pasa por la misma cadena de audio que
## la musica del juego, y lo que mida la calibracion sera el desfase real que
## va a tener el jugador.

const MIX_RATE := 44100
const CLICK_FREQ := 1600.0
const ACCENT_FREQ := 2400.0
## Constante de caida de la envolvente: un click corto y seco es mas facil de
## localizar en el tiempo que uno con cola.
const DECAY := 90.0
const CLICK_MS := 40.0
const AMPLITUDE := 0.6
## Silencio al final para que el stream no se corte justo tras el ultimo click.
const TAIL_S := 0.6


## Pista de `beats` clicks a `bpm`. El primero de cada compas suena mas agudo.
static func make_stream(bpm: float, beats: int, beats_per_bar: int = 4) -> AudioStreamWAV:
	var beat_s := 60.0 / bpm
	var total_samples := int((beat_s * beats + TAIL_S) * MIX_RATE)
	var click_samples := int(CLICK_MS / 1000.0 * MIX_RATE)

	var data := PackedByteArray()
	data.resize(total_samples * 2)   # 16 bits mono: 2 bytes por muestra

	for b in beats:
		var start := int(b * beat_s * MIX_RATE)
		var freq := ACCENT_FREQ if b % beats_per_bar == 0 else CLICK_FREQ
		for i in click_samples:
			var index := start + i
			if index >= total_samples:
				break
			var t := float(i) / MIX_RATE
			var sample := sin(TAU * freq * t) * exp(-t * DECAY) * AMPLITUDE
			data.encode_s16(index * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream


## Instante exacto de un beat, en ms. Es la referencia contra la que se compara
## el toque del jugador.
static func beat_time_ms(bpm: float, index: int) -> float:
	return index * 60000.0 / bpm
