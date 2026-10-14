"""Alarga un WAV repitiendolo desde el principio, empalmando en un inicio de compas.

Uso: python tools/extend_audio.py <entrada.wav> <salida.wav> <segundos> [--bpm B --offset S]

Sirve para tener una cancion de prueba de la duracion que pide un jefe (3 min)
a partir de un audio mas corto. El empalme cae en un inicio de compas y se
retoma desde el primer beat, asi que el ritmo sigue cuadrado; un fundido corto
evita el clic del corte.

Si no se pasan --bpm/--offset se detectan con gen_chart.
"""
import os
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_chart  # noqa: E402

BEATS_PER_BAR = 4
CROSSFADE_S = 0.010


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    src, dst, target_s = sys.argv[1], sys.argv[2], float(sys.argv[3])
    args = sys.argv[4:]
    bpm = offset = None
    for i, a in enumerate(args):
        if a == '--bpm':
            bpm = float(args[i + 1])
        elif a == '--offset':
            offset = float(args[i + 1])

    w = wave.open(src, 'rb')
    params = w.getparams()
    ch, sr = w.getnchannels(), w.getframerate()
    if w.getsampwidth() != 2:
        raise SystemExit("solo WAV PCM 16-bit")
    pcm = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').reshape(-1, ch).astype(np.float32)
    w.close()
    length_s = len(pcm) / sr

    if bpm is None or offset is None:
        mono, _ = gen_chart.read_mono(src)
        env, fps = gen_chart.onset_envelope(mono, sr)
        bpm, offset, _ = gen_chart.detect_beat(env, fps)

    bar = 60.0 / bpm * BEATS_PER_BAR
    # Ultimo inicio de compas antes del final (con un poco de margen).
    k = int((length_s - 0.2 - offset) // bar)
    cut_s = offset + k * bar
    out = pcm[:int(round(cut_s * sr))].copy()   # copia: el fundido no debe tocar pcm
    start = int(round(offset * sr))

    while len(out) < target_s * sr:
        # El fundido solapa `fade` muestras, asi que hay que pedir esas de mas:
        # si no, cuando falta menos que el fundido el bucle no avanza nunca.
        fade = min(int(CROSSFADE_S * sr), len(out))
        need = int(target_s * sr) - len(out) + fade
        piece = pcm[start:start + need].copy()
        fade = min(fade, len(piece))
        if len(piece) <= fade:
            raise SystemExit("el audio es demasiado corto para repetirlo")
        ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)[:, None]
        out[-fade:] = out[-fade:] * (1.0 - ramp) + piece[:fade] * ramp
        out = np.concatenate([out, piece[fade:]])

    out = np.clip(out[:int(target_s * sr)], -32768, 32767).astype('<i2')
    w = wave.open(dst, 'wb')
    w.setparams(params)
    w.writeframes(out.tobytes())
    w.close()
    print("bpm %.2f, offset %.0f ms, compas %.0f ms" % (bpm, offset * 1000, bar * 1000))
    print("empalme en %.3f s (compas %d), repite desde %.3f s" % (cut_s, k, offset))
    print("escrito %s: %.2f s" % (dst, len(out) / sr))


if __name__ == '__main__':
    main()
