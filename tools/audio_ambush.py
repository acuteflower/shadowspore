#!/usr/bin/env python3
"""Synthesized placeholders for the crossroad ambush (numpy + stdlib wave): a dark rising sting when the eyes open and a low impact with a
shimmering tail for the moment she is struck down. Writes assets/audio/ambush/*.wav deterministically."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "ambush"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = np.random.default_rng(23)


def tt(s):
    return np.arange(int(RATE * s)) / RATE


def band(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return np.fft.irfft(spec * ((f >= lo) & (f <= hi)), len(x))


def save(name, sig, level=0.7):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * level
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.int16(np.clip(sig, -1, 1) * 32767).tobytes())


# sting: two detuned low tones sliding up a minor second, a whispering noise swell, a thin high shimmer
t = tt(3.0)
env = np.minimum(1, t / 1.4) * np.minimum(1, (t[-1] - t) / 0.9)
glide = 55 + 6 * t / t[-1]
low = np.sin(2 * np.pi * np.cumsum(glide) / RATE) + 0.8 * np.sin(2 * np.pi * np.cumsum(glide * 1.0595 * 1.5) / RATE)
hiss = band(rng.normal(0, 1, len(t)), 1800, 6500) * (0.2 + 0.8 * (t / t[-1]) ** 2)
shim = np.sin(2 * np.pi * np.cumsum(1480 + 40 * np.sin(t * 5)) / RATE) * 0.07 * (t / t[-1]) ** 2
save("sting", (low * 0.8 + hiss * 0.35 + shim) * env, 0.7)

# impact: a sub drop, a crack of noise, a long shimmering tail
t = tt(2.4)
boom = np.sin(2 * np.pi * np.cumsum(120 * np.exp(-t * 3.0) + 38) / RATE) * np.exp(-t * 2.2)
crack = band(rng.normal(0, 1, len(t)), 300, 5000) * np.exp(-t * 14)
tail = (np.sin(2 * np.pi * 660 * t) + np.sin(2 * np.pi * 990.7 * t) * 0.7 + np.sin(2 * np.pi * 1318 * t) * 0.4) * np.exp(-t * 2.0) * 0.12 * (1 - np.exp(-t * 30))
save("impact", boom + crack * 0.9 + tail, 0.85)

# whoosh: a fast pass-by, noise sweeping up in pitch and fading away
t = tt(0.55)
sweep = band(rng.normal(0, 1, len(t)), 500, 5200) * np.sin(np.pi * np.clip(t / 0.55, 0, 1)) ** 1.6
tone = np.sin(2 * np.pi * np.cumsum(180 + 900 * (t / t[-1]) ** 2) / RATE) * 0.18 * np.sin(np.pi * np.clip(t / 0.55, 0, 1))
save("whoosh", sweep + tone, 0.6)

# slash: a bright steel ring over a hard crack, a shimmering tail, a low body hit
t = tt(0.9)
ring = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, a, d in ((1760, 0.5, 9), (2637, 0.35, 12), (3520, 0.25, 15), (5274, 0.15, 20), (880, 0.4, 7)))
crack = band(rng.normal(0, 1, len(t)), 1500, 8000) * np.exp(-t * 45)
body = np.sin(2 * np.pi * np.cumsum(140 * np.exp(-t * 18) + 55) / RATE) * np.exp(-t * 9)
shimmer = np.sin(2 * np.pi * 3100 * t + 6 * np.sin(2 * np.pi * 7 * t)) * 0.12 * np.exp(-t * 4)
save("slash", ring * 0.8 + crack * 0.9 + body * 0.9 + shimmer, 0.85)

# land: a heavy armoured landing, plate clanking, a tail of fading metal
t = tt(0.9)
thump = np.sin(2 * np.pi * np.cumsum(90 * np.exp(-t * 9) + 42) / RATE) * np.exp(-t * 7)
clank = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, a, d in ((620, 0.4, 11), (1010, 0.3, 14), (1730, 0.2, 18)))
plates = band(rng.normal(0, 1, len(t)), 700, 4500) * np.exp(-t * 22) * (1 + 0.5 * np.sin(2 * np.pi * 34 * t))
save("land", thump + clank + plates * 0.6, 0.85)
