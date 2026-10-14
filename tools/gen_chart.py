"""Genera un chart a partir de un WAV detectando tempo y fase del beat.

Uso: python tools/gen_chart.py <audio.wav> <salida.json> [--titulo T] [--cada N] [--dificultad D]

No reemplaza al modo edicion: sirve para tener un chart de prueba jugable sin
grabarlo a mano, y para comprobar que la rejilla esta bien enganchada al audio.

Metodo:
  1. Envelope de onset = flujo espectral sobre magnitud logaritmica, menos su
     media movil. El log realza los ataques suaves (voz, guitarra acustica),
     que un flujo lineal se come.
  2. Tempo y fase = componente de Fourier del envelope a la frecuencia del
     pulso. El angulo da la fase directamente, sin buscar a fuerza bruta.
  3. El pico de Fourier suele caer en un armonico (corcheas en vez de negras),
     asi que se baja de nivel mientras la rejilla resultante siga enganchada.
"""
import sys, os, json, wave
import numpy as np

HOP = 512
WIN = 2048
BPM_MIN, BPM_MAX = 60.0, 200.0
BEAT_BPM_MAX = 150.0        # por encima de esto asumimos que es un armonico
FOLD_MIN_RATIO = 1.5        # calidad minima para aceptar bajar de nivel


def read_mono(path):
    w = wave.open(path, 'rb')
    sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
    if sw != 2:
        raise SystemExit("solo WAV PCM 16-bit (sampwidth=%d)" % sw)
    data = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float32) / 32768.0
    w.close()
    if ch > 1:
        data = data.reshape(-1, ch).mean(axis=1)
    return data, sr


def onset_envelope(x, sr):
    frames = 1 + (len(x) - WIN) // HOP
    hann = np.hanning(WIN).astype(np.float32)
    spec = np.empty((frames, WIN // 2 + 1), dtype=np.float32)
    for i in range(frames):
        spec[i] = np.abs(np.fft.rfft(x[i * HOP: i * HOP + WIN] * hann))

    log_spec = np.log1p(1000.0 * spec)
    flux = np.maximum(0.0, np.diff(log_spec, axis=0)).sum(axis=1)
    flux = np.concatenate([[0.0], flux])

    fps = sr / HOP
    k = int(fps * 1.5) | 1
    env = np.maximum(0.0, flux - np.convolve(flux, np.ones(k) / k, mode='same'))
    return env / (env.std() + 1e-9), fps


def fourier_pulse(env, fps, bpm):
    """Fuerza (0..1) y offset en segundos del pulso a ese BPM."""
    n = np.arange(len(env))
    z = (env * np.exp(-2j * np.pi * (bpm / 60.0) * n / fps)).sum()
    period = 60.0 / bpm
    strength = np.abs(z) / (np.abs(env).sum() + 1e-9)
    offset = ((-np.angle(z) / (2.0 * np.pi)) * period) % period
    return strength, offset


def grid_ratio(env, fps, bpm, offset):
    """Energia de onset sobre la rejilla dividida por la de la anti-fase."""
    period = fps * 60.0 / bpm
    on = np.arange(offset * fps, len(env), period).astype(int)
    anti = np.arange(offset * fps + period / 2.0, len(env), period).astype(int)
    on, anti = on[on < len(env)], anti[anti < len(env)]
    return env[on].sum() / (env[anti].sum() + 1e-9)


def detect_beat(env, fps):
    """Devuelve (bpm, offset_s, ratio) a nivel de negra."""
    cands = np.arange(BPM_MIN, BPM_MAX, 0.05)
    strengths = [fourier_pulse(env, fps, b)[0] for b in cands]
    bpm = float(cands[int(np.argmax(strengths))])
    _, offset = fourier_pulse(env, fps, bpm)

    # Bajar de nivel (corchea -> negra) mientras la rejilla siga enganchada.
    # Al dividir el tempo aparecen dos fases posibles; nos quedamos con la mejor.
    while bpm / 2.0 >= BPM_MIN and bpm > BEAT_BPM_MAX:
        half = bpm / 2.0
        alt = offset + 60.0 / bpm
        best = max((grid_ratio(env, fps, half, o), o) for o in (offset, alt))
        if best[0] < FOLD_MIN_RATIO:
            break
        bpm, offset = half, best[1]

    return bpm, offset, grid_ratio(env, fps, bpm, offset)


def loudness_mask(x, sr, times_s, floor_ratio=0.12):
    """False donde la cancion practicamente no suena, para no poner notas en el silencio."""
    half = int(sr * 0.20)
    ref = np.sqrt(np.mean(x ** 2))
    keep = np.empty(len(times_s), dtype=bool)
    for i, t in enumerate(times_s):
        s = int(t * sr)
        seg = x[max(0, s - half): s + half]
        keep[i] = len(seg) > 0 and np.sqrt(np.mean(seg ** 2)) > ref * floor_ratio
    return keep


# Patron facil: movimiento corto y repetitivo, se lee de un vistazo.
EASY_PATTERN = [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 3, 2, 1, 0, 0, 1]


DIRECTION_LANES = [0, 1, 2, 3]
SPACE_LANE = 4


def exact_notes(env, fps, bpm, offset, dur, n, rng, space=0.15, chords=0.05, holds=0.04):
    """Exactamente `n` notas antes de `dur` segundos, sobre la rejilla del beat.

    Se prefieren las negras y, entre ellas, las que caen sobre un golpe fuerte;
    si no caben, se completan con corcheas. Una parte de las notas son acordes
    (dos a la vez), notas largas o el carril espacio, para que haya de todo.
    """
    beat = 60.0 / bpm
    quarters = np.arange(offset, dur - 0.4, beat)
    quarters = quarters[quarters > 1.0]
    eighths = quarters + beat / 2.0
    eighths = eighths[eighths < dur - 0.4]

    def strength(t):
        i = int(t * fps)
        return float(env[max(0, i - 2):i + 3].max()) if i < len(env) else 0.0

    n_chords = int(round(n * chords))
    n_times = n - n_chords

    # Reparto por compases: cada compas recibe su parte, asi la densidad es
    # pareja y una intro suave tambien lleva notas (elegir solo por fuerza las
    # amontonaria donde la musica pega mas). Dentro del compas ganan las negras
    # y, entre ellas, los golpes mas fuertes.
    bar = beat * 4
    bars = [b for b in np.arange(offset, dur - 0.4, bar)]
    groups = []
    for b in bars:
        group = [(1, strength(t), t) for t in quarters if b <= t < b + bar]
        group += [(0, strength(t), t) for t in eighths if b <= t < b + bar]
        if group:
            group.sort(reverse=True)
            groups.append(group)
    if n_times > sum(len(g) for g in groups):
        raise SystemExit("no caben %d notas en %.0f s a %.1f BPM" % (n, dur, bpm))
    # Cuota por compas; el resto, a los compases que mas suenan.
    quota = [n_times // len(groups)] * len(groups)
    by_energy = sorted(range(len(groups)), key=lambda i: -sum(c[1] for c in groups[i][:4]))
    for i in by_energy[:n_times - sum(quota)]:
        quota[i] += 1
    # Si un compas no tiene sitio, lo que sobra pasa a otros.
    spill = 0
    for i, g in enumerate(groups):
        if quota[i] > len(g):
            spill += quota[i] - len(g)
            quota[i] = len(g)
    for i in by_energy:
        while spill > 0 and quota[i] < len(groups[i]):
            quota[i] += 1
            spill -= 1
    times = sorted(t for g, q in zip(groups, quota) for _, _, t in g[:q])

    notes = []
    lane = rng.choice(DIRECTION_LANES)
    for t in times:
        if rng.random() < space:
            l = SPACE_LANE
        else:
            lane = (lane + rng.choice([-1, 1, 1, 2, -2])) % 4
            l = lane
        notes.append({"t": int(round(t * 1000)), "lane": l})

    # Acordes: a una nota de direccion se le suma otra a la vez en otro carril.
    singles = [i for i, nt in enumerate(notes) if nt["lane"] != SPACE_LANE]
    chord_extra = []
    for i in rng.sample(singles, min(n_chords, len(singles))):
        other = rng.choice([d for d in DIRECTION_LANES if d != notes[i]["lane"]])
        chord_extra.append({"t": notes[i]["t"], "lane": other})
    chord_times = {c["t"] for c in chord_extra}
    notes += chord_extra
    notes.sort(key=lambda nt: (nt["t"], nt["lane"]))

    # Largas: notas sueltas que se mantienen hasta poco antes de la siguiente
    # de su carril (como mucho 2 beats).
    by_lane = {}
    for nt in notes:
        by_lane.setdefault(nt["lane"], []).append(nt)
    loose = [nt for nt in notes if nt["t"] not in chord_times]
    for nt in rng.sample(loose, min(int(round(n * holds)), len(loose))):
        lane_notes = by_lane[nt["lane"]]
        k = lane_notes.index(nt)
        gap = (lane_notes[k + 1]["t"] - nt["t"] - 150) if k + 1 < len(lane_notes) else int(dur * 1000) - nt["t"] - 300
        length = min(gap, int(2 * beat * 1000))
        if length >= 300:
            nt["d"] = length
    return notes


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    title, every, difficulty = None, 1, "facil"
    exact, duration, seed = 0, 0.0, 1
    bpm_arg = offset_arg = None
    args = sys.argv[3:]
    for i, a in enumerate(args):
        if a == '--titulo':
            title = args[i + 1]
        elif a == '--cada':
            every = int(args[i + 1])
        elif a == '--dificultad':
            difficulty = args[i + 1]
        elif a == '--notas':
            exact = int(args[i + 1])
        elif a == '--duracion':
            duration = float(args[i + 1])
        elif a == '--semilla':
            seed = int(args[i + 1])
        elif a == '--bpm':
            bpm_arg = float(args[i + 1])
        elif a == '--offset':
            offset_arg = float(args[i + 1])

    x, sr = read_mono(src)
    dur = len(x) / sr
    env, fps = onset_envelope(x, sr)
    if bpm_arg is not None and offset_arg is not None:
        bpm, offset, ratio = bpm_arg, offset_arg, grid_ratio(env, fps, bpm_arg, offset_arg)
    else:
        bpm, offset, ratio = detect_beat(env, fps)
    beat = 60.0 / bpm

    end_ms = 0
    if exact > 0:
        import random
        rng = random.Random(seed)
        length = min(duration, dur) if duration > 0 else dur
        notes = exact_notes(env, fps, bpm, offset, length, exact, rng)
        end_ms = int(round(length * 1000))
    else:
        beats = np.arange(offset, dur - 0.5, beat)[::every]
        beats = beats[beats > 1.0]
        beats = beats[loudness_mask(x, sr, beats)]
        notes = [{"t": int(round(t * 1000)), "lane": EASY_PATTERN[i % len(EASY_PATTERN)]}
                 for i, t in enumerate(beats)]

    chart = {
        "version": 1,
        "title": title or os.path.splitext(os.path.basename(src))[0],
        "song_path": os.path.basename(src),
        "bpm": round(bpm, 2),
        "offset_ms": 0,
        "difficulty": difficulty,
        "end_ms": end_ms,
        "beat_offset_ms": int(round(offset * 1000)),
        "notes": notes,
    }
    with open(dst, 'w', encoding='utf-8') as f:
        json.dump(chart, f, indent=2, ensure_ascii=False)

    print("duracion    %.1f s%s" % (dur, ("  (chart hasta %.1f s)" % (end_ms / 1000)) if end_ms else ""))
    print("bpm         %.2f  (beat %.1f ms, offset %.0f ms)" % (bpm, beat * 1000, offset * 1000))
    print("enganche    %.2fx energia on-beat vs anti-fase  (>2 es solido)" % ratio)
    if exact:
        lanes = {}
        for nt in notes:
            lanes[nt["lane"]] = lanes.get(nt["lane"], 0) + 1
        print("notas       %d (pedidas %d) | largas %d | por carril %s" % (
            len(notes), exact, sum(1 for nt in notes if "d" in nt), dict(sorted(lanes.items()))))
    else:
        print("notas       %d, una cada %d beat(s) = %.0f ms" % (len(notes), every, beat * every * 1000))
    print("escrito en  %s" % dst)


if __name__ == '__main__':
    main()
