#!/usr/bin/env python3
"""Shadowspore 2.0 — Procedural Finisher Audio Generator (`tools/audio_finisher.py`).

Generates visceral 3-beat Finisher SFX in `assets/audio/sfx/`:
  1. `finisher_plunge.wav` : High-speed steel wind-cut -> heavy vertical chitin pierce + metallic ring
  2. `finisher_press.wav`  : Grinding chitin fracture under two-handed weight + deep 54 Hz Void-core sub-thud
  3. `finisher_rip.wav`    : Singing steel rip-out draw + crystalline Void-spore sac shatter
"""
from __future__ import annotations

import math
import pathlib
import wave
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[1]
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
SR = 44100


def save_wav(name: str, samples: np.ndarray, gain: float = 0.88) -> None:
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


def _one_pole_lp(x: np.ndarray, alpha: float) -> np.ndarray:
    y = np.empty_like(x)
    y[0] = alpha * x[0]
    for i in range(1, len(x)):
        y[i] = y[i - 1] + alpha * (x[i] - y[i - 1])
    return y


def _one_pole_hp(x: np.ndarray, coeff: float = 0.86) -> np.ndarray:
    y = np.empty_like(x)
    y[0] = x[0]
    for i in range(1, len(x)):
        y[i] = x[i] - coeff * x[i - 1]
    return y


def make_plunge() -> np.ndarray:
    """Beat 1: Fast overhead steel whoosh (0.00..0.06s) -> hard chitin-piercing slam & steel resonance."""
    dur = 0.36
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(701)

    # Short downward wind slice leading into impact at t = 0.045s
    whoosh_env = np.exp(-((t - 0.028) / 0.022) ** 2)
    whoosh = _one_pole_lp(rng.normal(0.0, 1.0, n), 0.18) * whoosh_env * 0.55

    # Impact at t0 = 0.045s
    ti = np.maximum(t - 0.045, 0.0)
    gate = (t >= 0.045).astype(np.float64)

    # Sub-punch (145 Hz -> 52 Hz)
    f_sub = 52.0 + 95.0 * np.exp(-ti * 38.0)
    sub = np.sin(np.cumsum(2.0 * math.pi * f_sub / SR)) * np.exp(-ti * 15.0) * gate

    # Crisp chitin crack transient (multi-impulse burst)
    crack_env = (
        np.exp(-((ti - 0.002) / 0.0035) ** 2)
        + 0.72 * np.exp(-((ti - 0.011) / 0.004) ** 2)
        + 0.48 * np.exp(-((ti - 0.021) / 0.005) ** 2)
    ) * gate
    crack = _one_pole_hp(rng.normal(0.0, 1.0, n), 0.78) * crack_env * 0.85

    # Pinned steel blade harmonic ring (980 Hz + 1640 Hz + 2490 Hz)
    steel_env = np.exp(-ti * 12.5) * (1.0 - np.exp(-ti * 220.0)) * gate
    steel = (
        0.48 * np.sin(2.0 * math.pi * 982.0 * ti)
        + 0.32 * np.sin(2.0 * math.pi * 1644.0 * ti)
        + 0.20 * np.sin(2.0 * math.pi * 2495.0 * ti)
    ) * steel_env * 0.44

    return whoosh + sub * 0.92 + crack + steel


def make_press() -> np.ndarray:
    """Beat 2: Brutal second deep press — grinding steel-on-chitin crunch + deep 54 Hz Void-sac rupture."""
    dur = 0.42
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(702)

    # Grinding chitin fractures across 0.00..0.14s as blade drives 4 px deeper
    grind_pulses = (
        0.85 * np.exp(-((t - 0.012) / 0.007) ** 2)
        + 1.00 * np.exp(-((t - 0.036) / 0.008) ** 2)
        + 0.90 * np.exp(-((t - 0.064) / 0.009) ** 2)
        + 0.65 * np.exp(-((t - 0.096) / 0.011) ** 2)
    )
    raw_noise = rng.normal(0.0, 1.0, n)
    band_crunch = _one_pole_lp(_one_pole_hp(raw_noise, 0.72), 0.32) * grind_pulses * 1.10

    # Heavy visceral sub-bass pulse peaking at 0.04s (118 Hz -> 46 Hz)
    f_thud = 46.0 + 72.0 * np.exp(-t * 24.0)
    thud = np.sin(np.cumsum(2.0 * math.pi * f_thud / SR)) * np.exp(-t * 9.5) * (1.0 - np.exp(-t * 140.0))

    # Pressurized Void-core hum & dark shimmer (218 Hz + 436 Hz FM)
    core_env = np.exp(-t * 7.5) * (1.0 - np.exp(-t * 55.0))
    core = (
        0.55 * np.sin(2.0 * math.pi * (218.0 + 24.0 * np.sin(t * 68.0)) * t)
        + 0.30 * np.sin(2.0 * math.pi * 438.0 * t)
    ) * core_env * 0.42

    return thud * 0.98 + band_crunch + core


def make_rip() -> np.ndarray:
    """Beat 3: Violent upward steel wrench + wet/crystalline Void-spore core shatter!"""
    dur = 0.48
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(703)

    # Singing steel draw sweeping upward in pitch (640 Hz -> 1820 Hz)
    f_draw = 640.0 + 1180.0 * (1.0 - np.exp(-t * 14.0))
    phase_d = np.cumsum(2.0 * math.pi * f_draw / SR)
    draw_env = np.exp(-t * 9.2) * (1.0 - np.exp(-t * 180.0))
    steel_draw = (0.62 * np.sin(phase_d) + 0.38 * np.sin(phase_d * 1.51)) * draw_env * 0.56

    # Rip-out air & ichor burst
    rip_env = np.exp(-t * 11.0) * (1.0 - np.exp(-t * 150.0))
    rip_noise = _one_pole_hp(rng.normal(0.0, 1.0, n), 0.80) * rip_env * 0.72

    # Crystalline Void-shard chimes scattering outward (staggered high partials)
    chimes = np.zeros(n, dtype=np.float64)
    for delay, freq, amp in [
        (0.015, 1320.0, 0.32),
        (0.042, 1760.0, 0.26),
        (0.078, 2240.0, 0.22),
        (0.115, 2680.0, 0.16),
    ]:
        tc = np.maximum(t - delay, 0.0)
        g = (t >= delay).astype(np.float64)
        chimes += amp * np.sin(2.0 * math.pi * freq * tc) * np.exp(-tc * 18.0) * g

    # Low release punch
    sub = np.sin(2.0 * math.pi * (82.0 * np.exp(-t * 12.0) + 42.0) * t) * np.exp(-t * 14.0) * 0.68

    return sub + steel_draw + rip_noise + chimes


def make_ready() -> np.ndarray:
    """Finisher V2 "Kern entblößt": a soft double heartbeat thump under a thin magenta shimmer (the core starts to beat)."""
    dur = 0.62
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    out = np.zeros(n, dtype=np.float64)
    for delay, amp in [(0.0, 1.0), (0.19, 0.72)]:
        tc = np.maximum(t - delay, 0.0)
        g = (t >= delay).astype(np.float64)
        f = 58.0 + 30.0 * np.exp(-tc * 30.0)
        out += amp * np.sin(2.0 * math.pi * f * tc) * np.exp(-tc * 16.0) * (1.0 - np.exp(-tc * 400.0)) * g
    shimmer_env = np.sin(np.clip(t / dur, 0.0, 1.0) * math.pi) ** 2
    shimmer = (np.sin(2.0 * math.pi * 2093.0 * t) + 0.6 * np.sin(2.0 * math.pi * 2637.0 * t + 0.4)) * shimmer_env * 0.06
    return out + shimmer


def make_apex() -> np.ndarray:
    """Finisher V2 apex hang: a sharp inhale of air and a rising metallic glint, ending in a breath of near-silence."""
    dur = 0.42
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(704)
    inhale_env = np.clip(t / 0.16, 0.0, 1.0) ** 1.6 * np.exp(-np.maximum(t - 0.18, 0.0) * 30.0)
    inhale = _one_pole_hp(_one_pole_lp(rng.normal(0.0, 1.0, n), 0.35), 0.6) * inhale_env * 0.5
    f_glint = 1900.0 + 1600.0 * np.clip(t / 0.2, 0.0, 1.0)
    phase = np.cumsum(2.0 * math.pi * f_glint / SR)
    glint_env = np.exp(-((t - 0.17) / 0.05) ** 2)
    glint = (np.sin(phase) + 0.4 * np.sin(phase * 2.01)) * glint_env * 0.32
    return inhale + glint


def make_core() -> np.ndarray:
    """Finisher V2 Kern-Bruch: deep sub-drop, the torn core shatters (bright crystal cascade), then the dust is sucked back in (reverse swell)."""
    dur = 0.9
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(705)
    sub = np.sin(2.0 * math.pi * (70.0 * np.exp(-t * 7.0) + 34.0) * t) * np.exp(-t * 6.0) * 0.8
    crack = _one_pole_hp(rng.normal(0.0, 1.0, n), 0.9) * np.exp(-t * 40.0) * 0.7
    shards = np.zeros(n, dtype=np.float64)
    for i in range(9):
        delay = 0.02 + i * 0.026 + rng.uniform(0.0, 0.012)
        freq = 2100.0 + rng.uniform(-300.0, 1400.0)
        tc = np.maximum(t - delay, 0.0)
        g = (t >= delay).astype(np.float64)
        shards += (0.24 - i * 0.018) * np.sin(2.0 * math.pi * freq * tc) * np.exp(-tc * 22.0) * g
    suck_env = np.clip((t - 0.38) / 0.4, 0.0, 1.0) ** 2.4 * (t < 0.8)
    suck = _one_pole_lp(rng.normal(0.0, 1.0, n), 0.08) * suck_env * 0.55
    implode = np.zeros(n, dtype=np.float64)
    tc = np.maximum(t - 0.8, 0.0)
    implode += np.sin(2.0 * math.pi * 48.0 * tc) * np.exp(-tc * 40.0) * (t >= 0.8) * 0.6
    return sub + crack + shards + suck + implode


def make_flick() -> np.ndarray:
    """Finisher V2 blade flick: a short whip of steel through the air and a spatter of droplets on the ground."""
    dur = 0.34
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    rng = np.random.default_rng(706)
    whip_env = np.exp(-((t - 0.035) / 0.018) ** 2)
    whip = _one_pole_hp(rng.normal(0.0, 1.0, n), 0.7) * whip_env * 0.7
    ring = np.sin(2.0 * math.pi * 3150.0 * t) * np.exp(-np.maximum(t - 0.04, 0.0) * 24.0) * (t >= 0.04) * 0.12
    drops = np.zeros(n, dtype=np.float64)
    for delay in (0.11, 0.135, 0.17, 0.2):
        tc = np.maximum(t - delay, 0.0)
        g = (t >= delay).astype(np.float64)
        drops += _one_pole_hp(rng.normal(0.0, 1.0, n), 0.5) * np.exp(-tc * 160.0) * g * 0.25
    return whip + ring + drops


def main() -> None:
    save_wav("finisher_plunge.wav", make_plunge(), 0.90)
    save_wav("finisher_press.wav", make_press(), 0.92)
    save_wav("finisher_rip.wav", make_rip(), 0.92)
    save_wav("finisher_ready.wav", make_ready(), 0.7)
    save_wav("finisher_apex.wav", make_apex(), 0.8)
    save_wav("finisher_core.wav", make_core(), 0.9)
    save_wav("finisher_flick.wav", make_flick(), 0.75)
    print("Generated 7 Finisher V2 audio files in", SFX_DIR)


if __name__ == "__main__":
    main()
