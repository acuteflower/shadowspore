#!/usr/bin/env python3
"""Synthesized placeholders for building (numpy + stdlib wave): a mallet knocking a nail into fir (three variants: a bright knock with a short iron ring, a duller one, a double tap)
and a beam set down on the ground. Writes assets/audio/hut/hammer_a.wav, hammer_b.wav, hammer_c.wav, beam_drop.wav deterministically."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "hut"
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


def knock(rng, length, f_wood, f_iron, ring, delay=0.0):
    n = int(RATE * length)
    t = np.arange(n) / RATE
    noise = band(rng.normal(size=n), 400, 2400)
    wood = np.sin(2 * np.pi * f_wood * t * (1 - 0.15 * t)) * np.exp(-t * 38) + noise * np.exp(-t * 70) * 0.7
    iron = np.sin(2 * np.pi * f_iron * t) * np.exp(-t * 55) * ring + np.sin(2 * np.pi * f_iron * 1.51 * t) * np.exp(-t * 80) * ring * 0.5
    sig = wood + iron
    if delay > 0:
        sig = np.concatenate([np.zeros(int(RATE * delay)), sig])
    return sig


for name, args in (("hammer_a", (210, 2300, 0.35)), ("hammer_b", (165, 1750, 0.2)), ("hammer_c", (190, 2050, 0.3))):
    rng = np.random.default_rng(len(name) * 7 + ord(name[-1]))
    sig = knock(rng, 0.45, *args)
    if name == "hammer_c":  # a second, softer tap right behind the first
        second = knock(rng, 0.3, 170, 1900, 0.15, 0.11) * 0.6
        out = np.zeros(max(len(sig), len(second)))
        out[:len(sig)] += sig
        out[:len(second)] += second
        sig = out
    save(name, sig)

rng = np.random.default_rng(99)
n = int(RATE * 0.7)
t = np.arange(n) / RATE
thud = np.sin(2 * np.pi * 68 * t * (1 - 0.3 * t)) * np.exp(-t * 9) + band(rng.normal(size=n), 120, 900) * np.exp(-t * 14) * 0.6
rattle = band(rng.normal(size=n), 800, 3200) * np.exp(-t * 18) * (np.sin(t * 90) > 0.2) * 0.15
save("beam_drop", thud + rattle)
print("audio_build written")
