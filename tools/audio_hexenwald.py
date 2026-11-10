#!/usr/bin/env python3
"""Synthesised placeholder sounds of the Hexenwald's mist (docs/hexenwald_nebel_konzept.md) -> assets/audio/hexenwald/ (numpy + stdlib, deterministic):
whisper_a/b/c (breathy voices without words, from the side), puff (a dull inward suck and a soft burst: a hallucination falls apart),
clear (a rising glassy breath: the Ohrringe der Klarheit push the mist back)."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "hexenwald")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(31)


def T(sec): return np.arange(int(R * sec)) / R


def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.6
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")


def breath(sec, formant, wobble):
    """Band-limited noise shaped like a mouth: a moving formant, syllables as slow lumps."""
    t = T(sec)
    n = rng.standard_normal(len(t))
    band = lowpass(n, 6) - lowpass(n, 40)
    f = formant * (1.0 + 0.25 * np.sin(2 * np.pi * wobble * t + rng.uniform(0, 6)))
    voiced = band * (0.55 + 0.45 * np.sin(2 * np.pi * np.cumsum(f) / R))
    syll = np.clip(np.sin(2 * np.pi * (2.6 + wobble) * t + rng.uniform(0, 6)), 0, 1) ** 1.5
    return voiced * syll * np.sin(np.pi * t / sec) ** 1.5


for name, sec, formant, wobble in (("whisper_a", 1.5, 900, 1.3), ("whisper_b", 2.1, 1300, 0.8), ("whisper_c", 1.1, 700, 2.1)):
    save(name, breath(sec, formant, wobble))

t = T(0.7)
suck = lowpass(rng.standard_normal(len(t)), 30) * np.clip(t / 0.32, 0, 1) ** 3 * (t < 0.32)
burst = lowpass(rng.standard_normal(len(t)), 9) * np.exp(-np.clip(t - 0.32, 0, 9) * 9) * (t >= 0.32)
thud = np.sin(2 * np.pi * 62 * t) * np.exp(-np.clip(t - 0.32, 0, 9) * 14) * (t >= 0.32)
save("puff", suck * 1.4 + burst * 0.7 + thud * 0.9)

t = T(1.6)
sweep = np.sin(2 * np.pi * np.cumsum(300 + 900 * (t / 1.6) ** 2) / R) * 0.25
air = (lowpass(rng.standard_normal(len(t)), 4) - lowpass(rng.standard_normal(len(t)), 30)) * 0.8
save("clear", (sweep + air) * np.sin(np.pi * t / 1.6) ** 2 + np.sin(2 * np.pi * 1760 * t) * np.exp(-np.clip(t - 1.0, 0, 9) * 5) * (t > 1.0) * 0.3)
print("hexenwald sounds written")
