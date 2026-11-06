#!/usr/bin/env python3
"""Synthesized placeholders for the quarry (numpy + stdlib wave): a pickaxe biting into stone, three variants (a hard tick of iron on rock, a short ring, a
rattle of falling chips, a low thump of the blow). Writes assets/audio/quarry/pick_a.wav, pick_b.wav, pick_c.wav deterministically."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "quarry"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050


def band(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return np.fft.irfft(spec * ((f >= lo) & (f <= hi)), len(x))


def save(name, sig, level=0.8):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * level
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.int16(np.clip(sig, -1, 1) * 32767).tobytes())


for i, (f1, f2, ring) in enumerate(((1850, 2740, 0.16), (2100, 3150, 0.12), (1650, 2480, 0.2))):
    r = np.random.default_rng(300 + i)
    t = np.arange(int(RATE * 0.7)) / RATE
    tick = band(r.normal(0, 1, len(t)), 2500, 9000) * np.exp(-t * 420)  # iron on rock
    ping = (np.sin(2 * np.pi * f1 * t) + 0.6 * np.sin(2 * np.pi * f2 * t) + 0.3 * np.sin(2 * np.pi * f1 * 2.76 * t)) * np.exp(-t / ring * 3.2) * 0.45
    thump = np.sin(2 * np.pi * (110 - 40 * np.minimum(t * 8, 1)) * t) * np.exp(-t * 22) * 0.9
    chips = np.zeros(len(t))
    for _ in range(18):  # chips skittering off the rock
        at = int((0.03 + r.random() * 0.4) * RATE)
        n = int(r.integers(40, 160))
        chips[at:at + n] += band(r.normal(0, 1, n), 1200, 6500) * np.exp(-np.arange(n) / (n / 4)) * r.uniform(0.08, 0.3)
    save(f"pick_{'abc'[i]}", tick * 0.8 + ping + thump + chips, 0.8)
print("wrote", sorted(p.name for p in OUT.glob("*.wav")))
