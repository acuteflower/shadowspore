#!/usr/bin/env python3
"""Synthesizes serene, crystalline zero-gravity movement sounds for Caelia's interstellar realm.
Outputs:
  - assets/audio/zero_g/glide_loop.wav (seamless airy astral resonance loop)
  - assets/audio/zero_g/boost.wav      (soft harmonic starlight impulse chime)
  - assets/audio/zero_g/brake.wav      (gentle stardust deceleration whisper)
  - assets/audio/zero_g/arrive.wav     (weightless lift-off celestial shimmer)
"""
from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "zero_g"
SR = 44100


def write_wav(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    peak = float(np.max(np.abs(samples))) if samples.size else 1.0
    if peak > 0.92:
        samples = samples * (0.92 / peak)
    pcm = np.clip(samples * 32767.0, -32767.0, 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())
    print("wrote", path)


def make_glide_loop() -> np.ndarray:
    """Seamless 3.0s celestial pad + filtered stardust shimmer."""
    dur = 3.0
    n = int(SR * dur)
    t = np.arange(n, dtype=np.float64) / SR
    # Integer-cycle harmonics over 3.0s so start == end seamlessly
    freqs = [(146.6667, 0.24), (220.0, 0.20), (330.0, 0.12), (440.0, 0.08), (660.0, 0.04)]
    sig = np.zeros(n, dtype=np.float64)
    for f, amp in freqs:
        mod = 0.85 + 0.15 * np.sin(2.0 * math.pi * (1.0 / dur) * t + f * 0.03)
        sig += amp * mod * np.sin(2.0 * math.pi * f * t)
    # Soft band-limited airy hiss (looped via FFT phase)
    rng = np.random.default_rng(707)
    noise = rng.standard_normal(n)
    spec = np.fft.rfft(noise)
    ff = np.fft.rfftfreq(n, 1.0 / SR)
    band = np.exp(-((ff - 1400.0) / 550.0) ** 2) * 0.12
    air = np.fft.irfft(spec * band, n=n)
    sig = sig * 0.42 + air * 0.28
    return sig


def make_boost() -> np.ndarray:
    """Soft upward harmonic starlight shimmer for Boost-Glide push-off."""
    dur = 0.58
    n = int(SR * dur)
    t = np.arange(n, dtype=np.float64) / SR
    env = np.sin(np.minimum(t / 0.045, 1.0) * math.pi * 0.5) * np.exp(-t * 5.2)
    sweep = 440.0 + 180.0 * (1.0 - np.exp(-t * 9.0))
    phase = np.cumsum(2.0 * math.pi * sweep / SR)
    sig = (
        0.48 * np.sin(phase)
        + 0.28 * np.sin(phase * 1.5)
        + 0.16 * np.sin(phase * 2.0 + 0.6)
        + 0.08 * np.sin(phase * 3.0)
    ) * env
    return sig * 0.62


def make_brake() -> np.ndarray:
    """Gentle downward breathy stardust deceleration whisper."""
    dur = 0.42
    n = int(SR * dur)
    t = np.arange(n, dtype=np.float64) / SR
    env = np.sin(np.minimum(t / 0.05, 1.0) * math.pi * 0.5) * np.exp(-t * 6.8)
    rng = np.random.default_rng(919)
    noise = rng.standard_normal(n)
    spec = np.fft.rfft(noise)
    ff = np.fft.rfftfreq(n, 1.0 / SR)
    band = np.exp(-((ff - 1050.0) / 480.0) ** 2)
    whoosh = np.fft.irfft(spec * band, n=n)
    tone = np.sin(2.0 * math.pi * (310.0 - 70.0 * t / dur) * t) * 0.22
    return (whoosh * 0.42 + tone) * env * 0.55


def make_arrive() -> np.ndarray:
    """Ethereal weightless arrival chord when stepping off gravity into Caelia's space."""
    dur = 1.25
    n = int(SR * dur)
    t = np.arange(n, dtype=np.float64) / SR
    env = np.sin(np.minimum(t / 0.14, 1.0) * math.pi * 0.5) * np.exp(-t * 2.35)
    notes = [293.66, 440.0, 554.37, 659.25, 880.0]  # D major 9 celestial chord
    sig = np.zeros(n, dtype=np.float64)
    for idx, f in enumerate(notes):
        delay = idx * 0.055
        mask = np.maximum(0.0, t - delay)
        e = np.where(t >= delay, np.sin(np.minimum(mask / 0.06, 1.0) * math.pi * 0.5) * np.exp(-mask * 2.8), 0.0)
        sig += (0.28 / (1.0 + 0.22 * idx)) * e * np.sin(2.0 * math.pi * f * mask)
    return sig * env * 0.72


if __name__ == "__main__":
    write_wav(ROOT / "glide_loop.wav", make_glide_loop())
    write_wav(ROOT / "boost.wav", make_boost())
    write_wav(ROOT / "brake.wav", make_brake())
    write_wav(ROOT / "arrive.wav", make_arrive())
