"""Synthesised placeholder sounds of Ellie's shadow step -> assets/audio/sfx/step_out.wav, step_in.wav (mono, 44.1 kHz, 16 bit).
  step_out  she tears into the void: a short airy push, a falling, inward-sucking hiss, digital crackle, and the rift snapping shut (a low thump)
  step_in   the same reversed in feel: the rift tears open (a sharp crack), a rising hiss that condenses, a soft landing
Run: py -3 tools/audio_shadow_step.py
"""
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"
RNG = np.random.default_rng(31)


def t(seconds: float) -> np.ndarray:
    return np.arange(int(SR * seconds)) / SR


def lowpass(x: np.ndarray, k: float) -> np.ndarray:
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc)
        y[i] = acc
    return y


def env(n: int, attack: float, release: float) -> np.ndarray:
    tt = np.arange(n) / SR
    a = np.clip(tt / max(attack, 1e-4), 0, 1)
    r = np.clip((tt[-1] - tt) / max(release, 1e-4), 0, 1)
    return a * r


def sweep_hiss(seconds: float, k0: float, k1: float) -> np.ndarray:
    """noise whose brightness glides from k0 to k1 (a whoosh)."""
    n = int(SR * seconds)
    x = RNG.standard_normal(n)
    y = np.empty(n)
    acc = 0.0
    lo = 0.0
    for i in range(n):
        k = k0 + (k1 - k0) * i / n
        acc += k * (x[i] - acc)
        lo += 0.02 * (acc - lo)
        y[i] = acc - lo
    return y


def crackle(seconds: float, density: float) -> np.ndarray:
    """digital glitch: sparse sample-and-hold bursts of square noise."""
    n = int(SR * seconds)
    y = np.zeros(n)
    i = 0
    while i < n:
        if RNG.random() < density:
            length = int(RNG.integers(60, 400))
            level = RNG.choice([-1.0, 1.0]) * RNG.uniform(0.3, 1.0)
            step = int(RNG.integers(4, 30))
            seg = np.repeat(RNG.choice([-1.0, 1.0], size=length // step + 1) * level, step)[:length]
            y[i:i + length] += seg[: n - i]
            i += length
        i += 200
    return y


def thump(seconds: float, f0: float, f1: float) -> np.ndarray:
    tt = t(seconds)
    f = f0 + (f1 - f0) * (tt / seconds)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 18.0)


def place(dst: np.ndarray, src: np.ndarray, at: float, gain: float) -> None:
    i = int(at * SR)
    end = min(len(dst), i + len(src))
    dst[i:end] += src[: end - i] * gain


def write(name: str, x: np.ndarray) -> None:
    x = x / max(1e-6, np.max(np.abs(x))) * 0.85
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def step_out() -> np.ndarray:
    out = np.zeros(int(SR * 0.42))
    push = sweep_hiss(0.12, 0.35, 0.12)
    place(out, push * env(len(push), 0.01, 0.08), 0.0, 0.45)
    suck = sweep_hiss(0.2, 0.55, 0.04)  # falls in brightness: drawn inwards
    place(out, suck * env(len(suck), 0.04, 0.1), 0.05, 0.7)
    place(out, lowpass(crackle(0.2, 0.5), 0.6), 0.06, 0.22)
    place(out, thump(0.18, 120.0, 45.0), 0.2, 0.8)
    return out


def step_in() -> np.ndarray:
    out = np.zeros(int(SR * 0.42))
    crack = RNG.standard_normal(int(SR * 0.025)) * np.exp(-np.arange(int(SR * 0.025)) / SR * 160.0)
    place(out, crack, 0.0, 0.6)
    rise = sweep_hiss(0.16, 0.04, 0.45)  # condenses: rises in brightness
    place(out, rise * env(len(rise), 0.06, 0.03), 0.01, 0.6)
    place(out, lowpass(crackle(0.14, 0.45), 0.6), 0.02, 0.2)
    place(out, thump(0.14, 70.0, 40.0), 0.17, 0.55)
    land = sweep_hiss(0.08, 0.2, 0.05)
    place(out, land * env(len(land), 0.005, 0.06), 0.17, 0.25)
    return out


if __name__ == "__main__":
    write("step_out", step_out())
    write("step_in", step_in())
    print("shadow step sounds written")
