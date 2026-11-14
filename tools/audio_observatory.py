#!/usr/bin/env python3
"""Procedural audio generator for Die Zenitwarte (Sonnenquarz-Öde Desert Observatory).
Writes 16-bit mono 22050 Hz WAVs into assets/audio/observatory/:
- gear_tick.wav     (subtle stone-and-brass celestial clockwork escapement click)
- gear_catch.wav    (metallic ratchet stutter + crystalline quartz release ping)
- wind_harp.wav     (warm pentatonic sintered-quartz aeolian harp harmonic chord)
- noon_chime.wav    (resonant golden astral bell triad for 12:00 Sundial Zenith)
- storm_surge.wav   (dry violet-amber arcane lightning discharge down the spire)
- ocular_chime.wav  (shimmering discovery chord for Polar Ocular & Star Portal)
"""
import math
import os
import wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "observatory")
SR = 22050


def save_wav(name: str, samples: np.ndarray, peak_target: float = 0.75) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    peak = float(np.max(np.abs(samples)))
    if peak > 1e-6:
        samples = samples / peak * peak_target
    pcm = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())
    print(f"wrote {name} ({len(pcm)} samples)")


def gen_gear_tick() -> np.ndarray:
    dur = 0.14
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    attack = np.minimum(t / 0.002, 1.0)
    click = attack * np.exp(-t * 58.0) * (
        0.55 * np.sin(2.0 * math.pi * 410.0 * t)
        + 0.35 * np.sin(2.0 * math.pi * 1180.0 * t)
        + 0.25 * np.sin(2.0 * math.pi * 2460.0 * t)
    )
    tail = np.exp(-t * 20.0) * 0.18 * np.sin(2.0 * math.pi * 185.0 * t)
    return click + tail


def gen_gear_catch() -> np.ndarray:
    dur = 0.62
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    sig = np.zeros_like(t)
    # Three metallic ratchet stutters then crisp crystal release ping
    for st in (0.0, 0.11, 0.22):
        dt = np.maximum(t - st, 0.0)
        gate = np.where(t >= st, np.minimum(dt / 0.003, 1.0), 0.0)
        sig += gate * np.exp(-dt * 42.0) * (
            0.55 * np.sin(2.0 * math.pi * 340.0 * dt)
            + 0.35 * np.sin(2.0 * math.pi * 920.0 * dt)
            + 0.20 * np.sin(2.0 * math.pi * 1790.0 * dt)
        )
    rel = np.maximum(t - 0.34, 0.0)
    rg = np.where(t >= 0.34, np.minimum(rel / 0.008, 1.0), 0.0)
    sig += rg * np.exp(-rel * 7.5) * (
        0.48 * np.sin(2.0 * math.pi * 880.0 * rel)
        + 0.32 * np.sin(2.0 * math.pi * 1318.51 * rel)
        + 0.18 * np.sin(2.0 * math.pi * 2093.0 * rel)
    )
    return sig


def gen_wind_harp() -> np.ndarray:
    dur = 1.65
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    env = np.minimum(t / 0.22, 1.0) * np.exp(-t * 1.95)
    # Warm D-pentatonic aeolian crystal chord (D5, F#5, A5, B5, E6)
    notes = [(0.00, 587.33, 0.42), (0.07, 739.99, 0.34), (0.15, 880.00, 0.30), (0.24, 987.77, 0.24), (0.34, 1318.51, 0.20)]
    sig = np.zeros_like(t)
    for st, freq, amp in notes:
        dt = np.maximum(t - st, 0.0)
        gate = np.where(t >= st, np.minimum(dt / 0.14, 1.0), 0.0)
        vib = 1.0 + 0.003 * np.sin(2.0 * math.pi * 4.8 * t)
        ph = 2.0 * math.pi * np.cumsum(freq * vib) / SR
        sig += gate * amp * np.exp(-dt * 2.1) * (0.8 * np.sin(ph) + 0.2 * np.sin(ph * 2.0))
    return sig * np.minimum(t / 0.08, 1.0) + 0.04 * env * np.sin(2.0 * math.pi * 293.66 * t)


def gen_noon_chime() -> np.ndarray:
    dur = 1.35
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    freqs = [(293.66, 0.45, 2.2), (587.33, 0.38, 2.5), (880.00, 0.30, 3.0), (1479.98, 0.22, 3.8)]
    sig = np.zeros_like(t)
    attack = np.minimum(t / 0.015, 1.0)
    for f, a, d in freqs:
        sig += a * attack * np.exp(-t * d) * np.sin(2.0 * math.pi * f * t)
    # Gentle golden tremolo shimmer
    sig *= 0.88 + 0.12 * np.sin(2.0 * math.pi * 7.5 * t)
    return sig


def gen_storm_surge() -> np.ndarray:
    dur = 0.72
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    rng = np.random.default_rng(9104)
    crackle = rng.normal(0.0, 1.0, len(t))
    # Dry resonant crackle (high-frequency sparkle, zero wet thunder)
    hi = crackle * np.sin(2.0 * math.pi * 1950.0 * t) * np.exp(-t * 9.5) * 0.42
    down = np.linspace(1120.0, 260.0, len(t))
    ph = 2.0 * math.pi * np.cumsum(down) / SR
    bolt = np.sin(ph) * np.minimum(t / 0.008, 1.0) * np.exp(-t * 6.5) * 0.55
    ping = np.sin(2.0 * math.pi * 1318.51 * t) * np.exp(-t * 5.0) * 0.25
    return hi + bolt + ping


def gen_ocular_chime() -> np.ndarray:
    dur = 1.05
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    notes = [(0.00, 440.00, 0.40), (0.06, 659.25, 0.36), (0.14, 987.77, 0.30), (0.22, 1318.51, 0.26)]
    sig = np.zeros_like(t)
    for st, freq, amp in notes:
        dt = np.maximum(t - st, 0.0)
        gate = np.where(t >= st, np.minimum(dt / 0.014, 1.0), 0.0)
        sig += gate * amp * np.exp(-dt * 3.1) * (
            0.78 * np.sin(2.0 * math.pi * freq * dt) + 0.22 * np.sin(2.0 * math.pi * freq * 1.5 * dt)
        )
    return sig


def main() -> None:
    save_wav("gear_tick.wav", gen_gear_tick(), 0.55)
    save_wav("gear_catch.wav", gen_gear_catch(), 0.68)
    save_wav("wind_harp.wav", gen_wind_harp(), 0.62)
    save_wav("noon_chime.wav", gen_noon_chime(), 0.72)
    save_wav("storm_surge.wav", gen_storm_surge(), 0.74)
    save_wav("ocular_chime.wav", gen_ocular_chime(), 0.68)


if __name__ == "__main__":
    main()
