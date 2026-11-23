#!/usr/bin/env python3
"""Shadowspore 2.0 — Procedural Audio Generator for Shadow Spider 2.0.

Generates subtle, organic Void-arachnid SFX in assets/audio/sfx/:
  - spider_hesitate.wav   : Curious spore-chitter + faint golden sun-quartz sear
  - spider_backstep.wav   : Taut Void-silk snap & dry skitter recoil
  - spider_venom.wav      : Pressurized chelicerae fang hiss
  - spider_exposed.wav    : Cracked chitin stagger & hollow spore-sac throb
  - spider_step_stone.wav : Delicate high-frequency tarsus click on stone/slate
"""

from __future__ import annotations

import math
import pathlib
import struct
import wave
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[1]
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
SR = 44100


def save_wav(name: str, samples: np.ndarray, gain: float = 0.82) -> None:
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    peak = float(np.max(np.abs(samples)))
    if peak > 1e-6:
        samples = samples / peak * gain
    pcm = np.clip(samples * 32767.0, -32768.0, 32767.0).astype(np.int16)
    out = SFX_DIR / name
    with wave.open(str(out), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())


def make_hesitate() -> np.ndarray:
    dur = 0.46
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(101)
    # Soft 3-pulse spore palp chitter (0.0..0.28s) followed by high crystalline quartz-sear hiss (0.28..0.46s)
    chitter_env = (
        np.exp(-((t - 0.05) / 0.025) ** 2)
        + 0.85 * np.exp(-((t - 0.13) / 0.022) ** 2)
        + 0.70 * np.exp(-((t - 0.20) / 0.020) ** 2)
    )
    carrier = np.sin(2.0 * math.pi * (410.0 + 95.0 * np.sin(t * 42.0)) * t)
    sub = 0.45 * np.sin(2.0 * math.pi * 192.0 * t)
    sear_env = np.where(t > 0.26, np.exp(-(t - 0.26) * 14.0) * (1.0 - np.exp(-(t - 0.26) * 85.0)), 0.0)
    noise = rng.normal(0.0, 1.0, n)
    # Simple one-pole highpass for crisp sizzle
    hp = np.empty_like(noise)
    hp[0] = noise[0]
    for i in range(1, n):
        hp[i] = noise[i] - 0.84 * noise[i - 1]
    quartz_ring = 0.32 * np.sin(2.0 * math.pi * 1480.0 * t) * sear_env
    return (carrier + sub) * chitter_env * 0.65 + hp * sear_env * 0.42 + quartz_ring


def make_backstep() -> np.ndarray:
    dur = 0.24
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(202)
    # Taut silk pluck (pitch drops fast 920 -> 240 Hz) + 3 rapid claw taps
    f_inst = 240.0 + 680.0 * np.exp(-t * 28.0)
    phase = np.cumsum(2.0 * math.pi * f_inst / SR)
    pluck = np.sin(phase) * np.exp(-t * 17.0)
    taps = (
        np.exp(-((t - 0.02) / 0.006) ** 2)
        + 0.75 * np.exp(-((t - 0.08) / 0.006) ** 2)
        + 0.55 * np.exp(-((t - 0.14) / 0.006) ** 2)
    )
    click = rng.normal(0.0, 1.0, n) * taps * 0.48
    return pluck * 0.75 + click


def make_venom() -> np.ndarray:
    dur = 0.30
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(303)
    env = (1.0 - np.exp(-t * 70.0)) * np.exp(-t * 9.5)
    bite_snap = np.sin(2.0 * math.pi * (560.0 * np.exp(-t * 22.0) + 120.0) * t) * np.exp(-t * 24.0)
    hiss = rng.normal(0.0, 1.0, n)
    # Band-shaped wet rasp
    bp = np.zeros_like(hiss)
    for i in range(2, n):
        bp[i] = 0.48 * (hiss[i] - hiss[i - 2]) + 0.55 * bp[i - 1]
    return bite_snap * 0.72 + bp * env * 0.65


def make_exposed() -> np.ndarray:
    dur = 0.38
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(404)
    # Chitin crack + hollow spore-bladder warble
    crack = rng.normal(0.0, 1.0, n) * (
        np.exp(-((t - 0.012) / 0.007) ** 2) + 0.65 * np.exp(-((t - 0.045) / 0.009) ** 2)
    )
    throb = np.sin(2.0 * math.pi * (165.0 - 55.0 * t / dur + 12.0 * np.sin(t * 36.0)) * t) * np.exp(-t * 6.5)
    return crack * 0.80 + throb * 0.68


def make_step_stone() -> np.ndarray:
    dur = 0.055
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(505)
    env = np.exp(-t * 95.0)
    tone = np.sin(2.0 * math.pi * 1620.0 * t) + 0.6 * np.sin(2.0 * math.pi * 2480.0 * t)
    tick = rng.normal(0.0, 1.0, n) * np.exp(-t * 150.0)
    return (tone * 0.45 + tick * 0.55) * env


def main() -> None:
    save_wav("spider_hesitate.wav", make_hesitate(), 0.72)
    save_wav("spider_backstep.wav", make_backstep(), 0.78)
    save_wav("spider_venom.wav", make_venom(), 0.80)
    save_wav("spider_exposed.wav", make_exposed(), 0.82)
    save_wav("spider_step_stone.wav", make_step_stone(), 0.45)
    print(f"Wrote 5 spider v2 SFX to {SFX_DIR}")


if __name__ == "__main__":
    main()
