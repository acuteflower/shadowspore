"""Synthesised placeholder sounds of the magic (docs/magie_konzept.md) -> assets/audio/magic/*.wav (mono, 44.1 kHz, 16 bit).
  cast_light   the staff drawn in and lifted: a glassy shimmer that rises, breath of air
  cast_root    the staff drawn back: a woody creak and a low, rising hum
  light_open   the staff strikes the ground: a soft thump, a bright chord of glass bells, a rush of light
  light_sear   a shadow creature burns in the light: a short crackling hiss
  light_pulse  SONNENKERN: a ring of light breaks out (a hollow, bright "vwomm")
  light_close  the light goes out: a falling, thinning shimmer
  root_seed    the seed of light flies: an airy whoosh with a green sparkle
  root_burst   the earth tears and the roots break out: a crack, crumbling soil, a deep groan of wood
  root_beat    a healing beat: a warm, soft wooden pluck with a bell above it
  root_wither  the roots wither: dry crackling, falling
  ready        the crystal is full again: a tiny clear ding
  socket       a stone set into the staff: wood clasping stone, a little ring
  cast_ember   GLUTSCHWARM drawn back: a rising, breathy roar of a bellows
  ember_launch the shards break out of the crystal: a crackling whoosh with a bright tick
  ember_hit    a shard strikes: a hot thud and a hiss
  ember_burst  GLUTHERZ: the last shard bursts: a crackling bloom
  ember_jump   FUNKENSPRUNG: the fire leaps: a quick rising crackle
  cast_veil    NEBELSCHLEIER: an airy, hollow breath falling and rising
  veil_on      the veil closes round someone: a soft swell of detuned glass, wind
  veil_off     it tears open: a breathy downward shimmer
  cast_maw     LEERENSCHLUND: a low, swelling drone that sucks in
  maw_open     the ground tears: a crack, a deep sub thump, a reversed rush
  maw_pull     its pull: a low wobbling hum (loops while something is caught)
  maw_snap     the jaws slam shut: a heavy wet snap, a bass hit, glass breaking
  maw_feed     life flows back: a rising shimmer with a heartbeat under it
  fork_strike  GABELSCHLAG: the Bleichgabel's two prongs ring against each other, a bright tuning-fork chord with a crack of lightning
Run: py -3 tools/audio_magic.py
"""
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "magic"
RNG = np.random.default_rng(11)


def t(seconds: float) -> np.ndarray:
    return np.arange(int(SR * seconds)) / SR


def noise(n: int) -> np.ndarray:
    return RNG.standard_normal(n)


def lowpass(x: np.ndarray, k: float) -> np.ndarray:
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc)
        y[i] = acc
    return y


def bandpass(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return lowpass(x, hi) - lowpass(x, lo)


def env(n: int, attack: float, release: float, curve: float = 2.0) -> np.ndarray:
    e = np.ones(n)
    a = max(int(attack * SR), 1)
    r = max(int(release * SR), 1)
    e[:a] = np.linspace(0.0, 1.0, a) ** curve
    e[-r:] *= np.linspace(1.0, 0.0, r) ** curve
    return e


def decay(n: int, seconds: float) -> np.ndarray:
    return np.exp(-np.arange(n) / SR / max(seconds, 1e-3))


def bell(freq: float, seconds: float, length: float, partials=((1.0, 1.0), (2.76, 0.4), (5.4, 0.18))) -> np.ndarray:
    x = t(length)
    out = np.zeros_like(x)
    for ratio, amp in partials:
        out += amp * np.sin(2 * np.pi * freq * ratio * x) * decay(len(x), seconds / ratio ** 0.5)
    return out


def sweep(f0: float, f1: float, length: float) -> np.ndarray:
    x = t(length)
    f = np.linspace(f0, f1, len(x))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def pad(x: np.ndarray, length: float) -> np.ndarray:
    n = int(SR * length)
    return np.pad(x, (0, max(n - len(x), 0)))[:n]


def norm(x: np.ndarray, peak: float = 0.8) -> np.ndarray:
    return x / max(np.max(np.abs(x)), 1e-6) * peak


def write(name: str, x: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    data = (np.clip(x, -1.0, 1.0) * 32767).astype(np.int16)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())


def crackle(n: int, density: float, seconds: float) -> np.ndarray:
    out = np.zeros(n)
    count = int(n / SR * density)
    for i in RNG.integers(0, n, count):
        k = np.arange(min(int(SR * seconds), n - i))
        out[i:i + len(k)] += RNG.uniform(-1, 1) * np.exp(-k / (SR * seconds * 0.25)) * np.sin(k * RNG.uniform(0.6, 1.4))
    return out


def main() -> None:
    L = 0.6
    n = int(SR * L)
    shimmer = sum(np.sin(2 * np.pi * f * t(L)) * (0.3 + 0.2 * np.sin(2 * np.pi * (3 + k) * t(L))) for k, f in enumerate((880, 1320, 1760, 2640)))
    rise = sweep(300, 900, L) * 0.4
    air = bandpass(noise(n), 0.05, 0.35) * 0.5
    write("cast_light", norm((shimmer * 0.5 + rise + air) * env(n, 0.35, 0.2), 0.45))

    creak = sweep(140, 220, 0.5) * (1 + 0.6 * np.sign(np.sin(2 * np.pi * 34 * t(0.5)))) * 0.3
    hum = sweep(90, 170, 0.5) * 0.5
    write("cast_root", norm((creak + hum + bandpass(noise(int(SR * 0.5)), 0.02, 0.12) * 0.4) * env(int(SR * 0.5), 0.2, 0.2), 0.45))

    L = 1.1
    n = int(SR * L)
    thump = pad(np.sin(2 * np.pi * 70 * t(0.25)) * decay(int(SR * 0.25), 0.08), L) * 0.9
    chord = sum(bell(f, 0.9, L) for f in (659.0, 830.6, 987.8, 1318.5)) * 0.35
    rush = bandpass(noise(n), 0.08, 0.6) * decay(n, 0.25) * 0.6
    write("light_open", norm(thump + chord + rush, 0.75))

    n = int(SR * 0.28)
    write("light_sear", norm((bandpass(noise(n), 0.3, 0.9) * 0.5 + crackle(n, 120, 0.01)) * env(n, 0.01, 0.15), 0.35))

    n = int(SR * 0.45)
    vw = sweep(220, 520, 0.45) * decay(n, 0.2) + bell(1046.5, 0.3, 0.45) * 0.4
    write("light_pulse", norm(vw * env(n, 0.02, 0.1), 0.55))

    L = 0.8
    n = int(SR * L)
    fall = sum(np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 0.55, n)) / SR) for f in (1760, 2217, 2637)) * decay(n, 0.35)
    write("light_close", norm(fall * env(n, 0.02, 0.3) + bandpass(noise(n), 0.1, 0.5) * decay(n, 0.2) * 0.3, 0.4))

    n = int(SR * 0.4)
    whoosh = bandpass(noise(n), 0.03, 0.25) * np.sin(np.linspace(0, np.pi, n)) ** 2
    sparkle = sum(bell(f, 0.12, 0.4) for f in (1975.5, 2637.0)) * 0.25
    write("root_seed", norm(whoosh + sparkle, 0.45))

    L = 1.2
    n = int(SR * L)
    crack = pad(bandpass(noise(int(SR * 0.08)), 0.2, 0.9) * decay(int(SR * 0.08), 0.02), L)
    soil = crackle(n, 400, 0.006) * decay(n, 0.35) * 0.6 + lowpass(noise(n), 0.03) * decay(n, 0.3) * 1.2
    groan = sweep(65, 95, L) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t(L))) * env(n, 0.15, 0.5) * 0.7
    write("root_burst", norm(crack + soil + groan, 0.75))

    n = int(SR * 0.6)
    pluck = sum(np.sin(2 * np.pi * f * t(0.6)) * decay(n, 0.12) * a for f, a in ((392.0, 1.0), (784.0, 0.4), (1176.0, 0.15)))
    write("root_beat", norm(pluck + bell(1568.0, 0.25, 0.6) * 0.25, 0.32))

    n = int(SR * 0.8)
    write("root_wither", norm(crackle(n, 260, 0.008) * np.linspace(1, 0.1, n) + lowpass(noise(n), 0.05) * decay(n, 0.3) * 0.6, 0.4))

    write("ready", norm(bell(2093.0, 0.15, 0.3) + bell(3136.0, 0.1, 0.3) * 0.4, 0.3))

    n = int(SR * 0.25)
    knock = pad(lowpass(noise(int(SR * 0.03)), 0.3) * decay(int(SR * 0.03), 0.008), 0.25)
    write("socket", norm(knock + bell(1760.0, 0.08, 0.25) * 0.5, 0.45))

    # ---- Glut
    L = 0.6
    n = int(SR * L)
    roar = bandpass(noise(n), 0.02, 0.18) * np.linspace(0.2, 1.0, n) ** 1.5
    write("cast_ember", norm((roar + sweep(110, 260, L) * 0.25) * env(n, 0.3, 0.08), 0.5))
    n = int(SR * 0.45)
    whoosh = bandpass(noise(n), 0.05, 0.4) * np.sin(np.linspace(0, np.pi, n)) ** 1.5
    write("ember_launch", norm(whoosh + crackle(n, 300, 0.006) * 0.8 + bell(2349.0, 0.06, 0.45) * 0.3, 0.55))
    n = int(SR * 0.35)
    thud = pad(np.sin(2 * np.pi * 95 * t(0.12)) * decay(int(SR * 0.12), 0.03), 0.35)
    write("ember_hit", norm(thud + bandpass(noise(n), 0.25, 0.8) * decay(n, 0.12) * 0.6 + crackle(n, 160, 0.005) * 0.5, 0.5))
    n = int(SR * 0.7)
    bloom = bandpass(noise(n), 0.04, 0.35) * decay(n, 0.25) + crackle(n, 520, 0.006) * decay(n, 0.35)
    write("ember_burst", norm(bloom + pad(np.sin(2 * np.pi * 70 * t(0.2)) * decay(int(SR * 0.2), 0.06), 0.7), 0.65))
    n = int(SR * 0.3)
    write("ember_jump", norm(crackle(n, 420, 0.004) * np.linspace(0.3, 1.0, n) + sweep(600, 1400, 0.3) * 0.15 * env(n, 0.05, 0.1), 0.4))

    # ---- Nebel
    L = 0.75
    n = int(SR * L)
    breath = bandpass(noise(n), 0.01, 0.08) * np.sin(np.linspace(0, np.pi, n)) ** 2
    hollow = (np.sin(2 * np.pi * np.cumsum(np.linspace(330, 250, n)) / SR) + np.sin(2 * np.pi * np.cumsum(np.linspace(334, 254, n)) / SR)) * 0.2
    write("cast_veil", norm((breath + hollow) * env(n, 0.25, 0.25), 0.4))
    L = 1.0
    n = int(SR * L)
    glass = sum(np.sin(2 * np.pi * f * t(L)) * (0.5 + 0.5 * np.sin(2 * np.pi * (0.7 + k * 0.3) * t(L))) for k, f in enumerate((587.3, 591.0, 880.0, 884.5, 1174.7)))
    write("veil_on", norm((glass * 0.25 + bandpass(noise(n), 0.02, 0.15) * 0.6) * env(n, 0.3, 0.45), 0.4))
    n = int(SR * 0.7)
    fall = sum(np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 0.6, n)) / SR) for f in (1174.7, 1480.0)) * decay(n, 0.3)
    write("veil_off", norm(fall * 0.4 + bandpass(noise(n), 0.03, 0.2) * decay(n, 0.25), 0.35))

    # ---- Leere
    L = 0.9
    n = int(SR * L)
    drone = (sweep(45, 70, L) + sweep(90, 140, L) * 0.4) * np.linspace(0.1, 1.0, n) ** 2
    suck = bandpass(noise(n), 0.02, 0.2) * np.linspace(0.0, 1.0, n) ** 3
    write("cast_maw", norm((drone + suck * 0.7) * env(n, 0.1, 0.05), 0.55))
    L = 1.2
    n = int(SR * L)
    crack = pad(bandpass(noise(int(SR * 0.06)), 0.3, 0.95) * decay(int(SR * 0.06), 0.015), L)
    sub = pad(np.sin(2 * np.pi * np.cumsum(np.linspace(60, 30, int(SR * 0.6))) / SR) * decay(int(SR * 0.6), 0.25), L)
    rev = (bandpass(noise(n), 0.03, 0.3) * np.linspace(0.0, 1.0, n) ** 2)[::-1] * 0.0 + bandpass(noise(n), 0.03, 0.3) * np.linspace(1.0, 0.0, n) ** 2 * 0.5
    write("maw_open", norm(crack + sub * 1.2 + rev, 0.75))
    L = 0.6
    n = int(SR * L)
    wob = sweep(55, 55, L) * (0.6 + 0.4 * np.sin(2 * np.pi * 6 * t(L))) + sweep(110, 108, L) * 0.3
    write("maw_pull", norm(wob * env(n, 0.08, 0.15), 0.4))
    L = 1.0
    n = int(SR * L)
    snap = pad(lowpass(noise(int(SR * 0.05)), 0.4) * decay(int(SR * 0.05), 0.01), L)
    bass = pad(np.sin(2 * np.pi * np.cumsum(np.linspace(90, 35, int(SR * 0.5))) / SR) * decay(int(SR * 0.5), 0.15), L)
    shards = crackle(n, 700, 0.004) * decay(n, 0.2) + sum(bell(f, 0.2, L) for f in (1975.5, 2793.8, 3520.0)) * 0.12
    write("maw_snap", norm(snap * 1.2 + bass * 1.3 + shards, 0.85))
    L = 0.9
    n = int(SR * L)
    beat = pad(np.sin(2 * np.pi * 60 * t(0.12)) * decay(int(SR * 0.12), 0.04), L) + np.roll(pad(np.sin(2 * np.pi * 55 * t(0.12)) * decay(int(SR * 0.12), 0.04), L), int(SR * 0.18)) * 0.7
    shimmer = sum(np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 1.5, n)) / SR) for f in (659.3, 987.8)) * env(n, 0.2, 0.3) * 0.25
    write("maw_feed", norm(beat + shimmer, 0.5))

    # ---- the Bleichgabel
    L = 1.1
    n = int(SR * L)
    fork = sum(np.sin(2 * np.pi * f * t(L)) * decay(n, 0.6) * a for f, a in ((440.0, 1.0), (443.5, 0.8), (880.0, 0.3), (1318.5, 0.15)))
    zap = pad(bandpass(noise(int(SR * 0.12)), 0.3, 0.95) * decay(int(SR * 0.12), 0.03) + crackle(int(SR * 0.12), 900, 0.003), L)
    write("fork_strike", norm(fork * 0.6 + zap * 0.8, 0.6))
    print("magic sounds written")


if __name__ == "__main__":
    main()
