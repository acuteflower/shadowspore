#!/usr/bin/env python3
"""Synthesized placeholders for the open-air beds (numpy + stdlib wave): a day bed (soft wind, far bird phrases, a
bee drone) and a night bed (crickets, a low far void hum). Both are 24 s. Writes assets/audio/ambience/{day,night}.wav."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "ambience"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
LEN = 24.0
rng = np.random.default_rng(91)
t = np.arange(int(RATE * LEN)) / RATE


def band(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return np.fft.irfft(spec * ((f >= lo) & (f <= hi)), len(x))


def swell(rate, phase):
    return 0.55 + 0.45 * np.sin(2 * np.pi * (t / LEN * rate) + phase)  # whole cycles per loop: seamless


def chirp(at, f0, f1, dur, amp):
    s = np.zeros_like(t)
    i0 = int(at * RATE)
    n = int(dur * RATE)
    if i0 + n >= len(t):
        return s
    k = np.arange(n) / RATE
    ph = 2 * np.pi * (f0 * k + (f1 - f0) * k * k / (2 * dur))
    s[i0:i0 + n] = np.sin(ph) * np.sin(np.pi * k / dur) ** 2 * amp
    return s


def save(name, sig, level=0.5):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * level
    ramp = int(0.05 * RATE)
    sig[:ramp] *= np.linspace(0, 1, ramp)
    sig[-ramp:] *= np.linspace(1, 0, ramp)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.int16(np.clip(sig, -1, 1) * 32767).tobytes())


# day: wind in leaves, a few far birds, a faint bee
wind = band(rng.normal(size=len(t)), 300, 1800) * swell(3, 0.0) * 0.5
birds = np.zeros_like(t)
for at in rng.uniform(1, LEN - 2, 9):
    f = rng.uniform(2400, 4200)
    for k in range(rng.integers(2, 5)):
        birds += chirp(at + k * 0.16, f, f * rng.uniform(0.8, 1.3), 0.11, 0.35)
bee = np.sin(2 * np.pi * 190 * t + 3 * np.sin(2 * np.pi * 5 * t)) * swell(2, 1.0) ** 3 * 0.07
save("day", wind + birds * 0.6 + bee)

# night: crickets (4.3 kHz bursts in trills), a low far hum
crick = np.zeros_like(t)
for start in rng.uniform(0, LEN - 3, 6):
    for k in range(int(rng.integers(8, 20))):
        crick += chirp(start + k * 0.085, 4300, 4350, 0.04, 0.3)
hum = np.sin(2 * np.pi * 55 * t) * 0.08 * swell(2, 0.5) + band(rng.normal(size=len(t)), 60, 220) * 0.05
save("night", crick * 0.7 + hum + band(rng.normal(size=len(t)), 200, 900) * 0.03 * swell(3, 2.0))
