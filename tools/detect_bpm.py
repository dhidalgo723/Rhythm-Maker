"""Detecta el tempo del audio de uno o varios charts y lo guarda en ellos.

Las grabaciones del juego se hacen tocando y se guardan con bpm 0. Algunas
habilidades de jefe van al pulso (Polirritmia, Zoom de Camara) y lo necesitan.
Esto analiza el audio con el mismo metodo que tools/gen_chart.py y escribe
"bpm" y "beat_offset_ms" en cada chart.json. Las notas no se tocan.

Uso:  python tools/detect_bpm.py roguelike/songs/*.chart.json [--force]
      (sin --force se saltan los charts que ya tienen bpm)
Necesita numpy y soundfile (pip install soundfile): lee WAV, MP3 y OGG.
"""
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).parent))
import gen_chart  # noqa: E402  (onset_envelope y detect_beat)


def read_mono(path):
    data, sr = sf.read(str(path), dtype='float32', always_2d=True)
    return data.mean(axis=1), sr


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    force = '--force' in sys.argv
    if not args:
        raise SystemExit(__doc__)
    for chart_path in map(Path, args):
        chart = json.loads(chart_path.read_text(encoding='utf-8'))
        if float(chart.get('bpm', 0)) > 0 and not force:
            print('%-32s ya tiene %.1f BPM, se salta' % (chart_path.name, chart['bpm']))
            continue
        audio = chart_path.parent / chart['song_path']
        x, sr = read_mono(audio)
        env, fps = gen_chart.onset_envelope(x, sr)
        bpm, offset, ratio = gen_chart.detect_beat(env, fps)
        chart['bpm'] = round(float(bpm), 2)
        chart['beat_offset_ms'] = int(round(offset * 1000))
        chart_path.write_text(json.dumps(chart, ensure_ascii=False, indent=1), encoding='utf-8')
        print('%-32s %6.1f BPM  offset %4d ms  enganche %.1fx (>2 es solido)' % (
            chart_path.name, bpm, chart['beat_offset_ms'], ratio))


if __name__ == '__main__':
    main()
