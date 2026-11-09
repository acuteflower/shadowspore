"""Synthesised placeholder sounds of the sword's heavy blow -> assets/audio/heavy/*.wav (mono, 44.1 kHz, 16 bit).
  draw   the blade is pulled up (leather and steel scrape, rising)
  drop   the charge is dropped (the blade sinks, a soft rattle)
  ready  the blow is worth letting go (a small clear tick)
  full   fully charged (a bright, short shimmer)
  swing  the chop (a heavy, low whoosh that falls in pitch)
  hit    the blade bites (thump + steel clank)
  thud   the blow lands in the ground (low, dusty boom)
Run: py -3 tools/audio_heavy.py
"""
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "heavy"
RNG = np.random.default_rng(7)


def t(seconds: float) -> np.ndarray:
    return np.arange(int(SR * seconds)) / SR


def noise(n: int) -> np.ndarray:
    return RNG.standard_normal(n)


def lowpass(x: np.ndarray, k: float) -> np.ndarray:
    """one-pole low pass, k 0..1 (higher = brighter)."""
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
    print("wrote", name, len(data) / SR, "s")


def tone(freq, seconds: float) -> np.ndarray:
    """phase-accumulated sine (freq may be an array)."""
    f = freq if isinstance(freq, np.ndarray) else np.full(int(SR * seconds), float(freq))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def draw() -> np.ndarray:
    d = 0.30
    n = int(SR * d)
    scrape = bandpass(noise(n), 0.02, 0.35) * np.linspace(0.5, 1.0, n)
    ring = tone(np.linspace(700, 1500, n), d) * 0.12 * np.linspace(0.2, 1.0, n)
    x = (scrape * 1.6 + ring) * env(n, 0.04, 0.12)
    return norm(x, 0.55)


def drop() -> np.ndarray:
    d = 0.22
    n = int(SR * d)
    x = bandpass(noise(n), 0.01, 0.2) * np.linspace(1.0, 0.2, n) + tone(np.linspace(420, 180, n), d) * 0.2
    return norm(x * env(n, 0.01, 0.12), 0.4)


def ready() -> np.ndarray:
    d = 0.14
    n = int(SR * d)
    x = (tone(1320, d) * 0.6 + tone(1980, d) * 0.25) * env(n, 0.003, 0.11, 3.0)
    return norm(x, 0.35)


def full() -> np.ndarray:
    d = 0.42
    n = int(SR * d)
    x = sum(tone(f, d) * a for f, a in ((1568, 0.5), (2093, 0.35), (3136, 0.2), (2349, 0.25)))
    x = x * env(n, 0.004, 0.36, 3.0) * (0.8 + 0.2 * np.sin(2 * np.pi * 26 * t(d)))
    return norm(x, 0.4)


def swing() -> np.ndarray:
    d = 0.40
    n = int(SR * d)
    k = np.linspace(0.0, 1.0, n)
    body = bandpass(noise(n), 0.01, 0.12 + 0.3 * np.sin(np.pi * k).mean()) * np.sin(np.pi * k ** 0.7) ** 1.3
    low = tone(np.linspace(170, 62, n), d) * 0.5 * np.sin(np.pi * k)
    hiss = bandpass(noise(n), 0.12, 0.6) * np.sin(np.pi * np.clip(k * 1.4, 0, 1)) * 0.35
    return norm((body * 2.0 + low + hiss) * env(n, 0.02, 0.1), 0.85)


def hit() -> np.ndarray:
    d = 0.45
    n = int(SR * d)
    k = t(d)
    thump = tone(np.linspace(190, 55, n), d) * np.exp(-k * 16.0)
    clank = sum(tone(f, d) * a * np.exp(-k * r) for f, a, r in ((880, 0.4, 18.0), (1450, 0.3, 24.0), (2210, 0.25, 30.0), (3100, 0.12, 40.0)))
    crack = lowpass(noise(n), 0.5) * np.exp(-k * 90.0)
    return norm(thump * 1.3 + clank * 0.7 + crack * 0.6, 0.9)


def thud() -> np.ndarray:
    d = 0.6
    n = int(SR * d)
    k = t(d)
    boom = tone(np.linspace(110, 38, n), d) * np.exp(-k * 9.0)
    dust = lowpass(noise(n), 0.12) * np.exp(-k * 14.0) * 0.8
    return norm(boom * 1.4 + dust, 0.9)


if __name__ == "__main__":
    for name, fn in (("draw", draw), ("drop", drop), ("ready", ready), ("full", full), ("swing", swing), ("hit", hit), ("thud", thud)):
        write(name, fn())
