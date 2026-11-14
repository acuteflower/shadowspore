#!/usr/bin/env python3
"""Generate Ellie's complete Foley footstep sound suite for Shadowspore.

Outputs 208 mono 16-bit 44.1 kHz WAV files into `assets/audio/steps/`:
    <surface>_<gait>_<1..4>.wav

Surfaces (13):
    grass, steppe, path, slope, stone, mine_stone, quartz,
    sand, wood, bed, mud, shallow_water, puddle

Gaits (4):
    sneak  - soft ball-of-foot placement, hushed brush, zero sharp heel knock
    walk   - natural two-stage leather-boot heel-to-toe articulation
    jog    - brisk springy midfoot strike, lively texture
    sprint - firm forefoot drive + energetic kick-up scatter / splash tail

Uses noise-excited physical Foley acoustics (damped body formants, micro-grain
textures, hydrodynamic liquid bursts) so no step ever sounds tonal or synthetic.
Preserves non-footstep swim files in `assets/audio/steps/` (`swim_*.mp3`).
"""
from __future__ import annotations

import wave
from pathlib import Path
from typing import Callable

import numpy as np
from scipy import signal

SR: int = 44100
OUT_DIR: Path = Path(__file__).resolve().parent.parent / "assets" / "audio" / "steps"
GAITS: tuple[str, ...] = ("sneak", "walk", "jog", "sprint")
VARIANTS: int = 4


# ---------------------------------------------------------------------------
# Core DSP & Foley Building Blocks
# ---------------------------------------------------------------------------

def butter_band(sig: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    if sig.size < 16:
        return sig
    nyq = 0.5 * SR
    lo_n = max(20.0 / nyq, min(lo / nyq, 0.95))
    hi_n = max(lo_n + 0.01, min(hi / nyq, 0.985))
    sos = signal.butter(order, [lo_n, hi_n], btype="bandpass", output="sos")
    return signal.sosfilt(sos, sig)


def butter_lp(sig: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    if sig.size < 16:
        return sig
    nyq = 0.5 * SR
    wn = max(25.0 / nyq, min(cutoff / nyq, 0.985))
    sos = signal.butter(order, wn, btype="lowpass", output="sos")
    return signal.sosfilt(sos, sig)


def butter_hp(sig: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    if sig.size < 16:
        return sig
    nyq = 0.5 * SR
    wn = max(20.0 / nyq, min(cutoff / nyq, 0.96))
    sos = signal.butter(order, wn, btype="highpass", output="sos")
    return signal.sosfilt(sos, sig)


def resonator(sig: np.ndarray, freq: float, q: float) -> np.ndarray:
    if sig.size < 8:
        return sig
    nyq = 0.5 * SR
    w0 = max(35.0 / nyq, min(freq / nyq, 0.94))
    b, a = signal.iirpeak(w0, Q=q)
    return signal.lfilter(b, a, sig)


def ad_env(n: int, attack_s: float, decay_s: float) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / SR
    att = max(attack_s, 0.0003)
    dec = max(decay_s, 0.0012)
    rise = np.clip(t / att, 0.0, 1.0)
    smooth_rise = 0.5 - 0.5 * np.cos(np.pi * rise)
    fall = np.exp(-np.maximum(t - att * 0.55, 0.0) / dec)
    return smooth_rise * fall


def add_at(buf: np.ndarray, snippet: np.ndarray, t_sec: float, gain: float = 1.0) -> None:
    if gain == 0.0 or snippet.size == 0:
        return
    idx = max(0, int(round(t_sec * SR)))
    if idx >= buf.size:
        return
    end = min(buf.size, idx + snippet.size)
    buf[idx:end] += snippet[: end - idx] * gain


def foley_thud(
    rng: np.random.Generator,
    freq: float,
    decay_s: float,
    attack_s: float = 0.0012,
    q: float = 1.6,
) -> np.ndarray:
    """Physical noise-excited damped impact thud (warm Foley weight, zero drum-synth sine ring)."""
    dur = max(0.035, decay_s * 5.2 + attack_s)
    n = max(24, int(round(dur * SR)))
    raw = rng.standard_normal(n) * ad_env(n, attack_s, decay_s * 0.75)
    low_pad = butter_band(raw, max(42.0, freq * 0.52), min(freq * 2.1, 600.0), order=2)
    body = resonator(raw, freq, q=q) * ad_env(n, attack_s, decay_s)
    return low_pad * 0.85 + body * 0.55


def leather_sole_step(
    buf: np.ndarray,
    rng: np.random.Generator,
    gait: str,
    hardness: float = 0.5,
    body_freq: float = 125.0,
) -> tuple[float, float, float]:
    """Ellie's supple leather boot weight & heel-to-toe articulation; returns (t_heel, t_toe, energy)."""
    if gait == "sneak":
        t_heel = 0.0012
        t_toe = rng.uniform(0.036, 0.050)
        energy = 0.44
        # Soft ball-of-foot weight placement (slow cushioned attack, no sharp heel strike)
        pad = foley_thud(rng, body_freq * 0.90, decay_s=0.016, attack_s=0.0065, q=1.3)
        add_at(buf, pad, t_heel, 0.42 * (0.75 + 0.35 * hardness))
        # Subtle soft leather/cloth movement whisper
        fn = int(0.055 * SR)
        cloth = butter_band(rng.standard_normal(fn), 320.0, 1350.0, order=2) * ad_env(fn, 0.012, 0.020)
        add_at(buf, cloth, 0.005, 0.07)
        return t_heel, t_toe, energy

    if gait == "walk":
        t_heel = 0.0010
        t_toe = rng.uniform(0.027, 0.036)
        energy = 0.74
        heel = foley_thud(rng, body_freq, decay_s=0.011, attack_s=0.0014, q=1.55)
        toe = foley_thud(rng, body_freq * 1.18, decay_s=0.0095, attack_s=0.0019, q=1.5)
        sn = int(0.022 * SR)
        sole = butter_band(rng.standard_normal(sn), 380.0, 1500.0 + 1100.0 * hardness, order=2) * ad_env(sn, 0.0011, 0.0042)
        add_at(buf, heel, t_heel, 0.55)
        add_at(buf, sole, t_heel, 0.18 + 0.28 * hardness)
        add_at(buf, toe, t_toe, 0.36)
        return t_heel, t_toe, energy

    if gait == "jog":
        t_heel = 0.0009
        t_toe = rng.uniform(0.013, 0.019)
        energy = 0.92
        mid = foley_thud(rng, body_freq * 1.06, decay_s=0.0105, attack_s=0.0011, q=1.6)
        push = foley_thud(rng, body_freq * 1.24, decay_s=0.0085, attack_s=0.0014, q=1.5)
        sn = int(0.020 * SR)
        sole = butter_band(rng.standard_normal(sn), 420.0, 1750.0 + 1300.0 * hardness, order=2) * ad_env(sn, 0.0009, 0.0038)
        add_at(buf, mid, t_heel, 0.64)
        add_at(buf, sole, t_heel, 0.24 + 0.32 * hardness)
        add_at(buf, push, t_toe, 0.40)
        return t_heel, t_toe, energy

    # sprint
    t_heel = 0.0008
    t_toe = rng.uniform(0.015, 0.023)
    energy = 1.10
    drive = foley_thud(rng, body_freq * 1.10, decay_s=0.0115, attack_s=0.0009, q=1.65)
    push = foley_thud(rng, body_freq * 1.30, decay_s=0.0090, attack_s=0.0012, q=1.55)
    sn = int(0.022 * SR)
    sole = butter_band(rng.standard_normal(sn), 460.0, 2000.0 + 1500.0 * hardness, order=2) * ad_env(sn, 0.0008, 0.0040)
    add_at(buf, drive, t_heel, 0.72)
    add_at(buf, sole, t_heel, 0.28 + 0.36 * hardness)
    add_at(buf, push, t_toe, 0.46)
    return t_heel, t_toe, energy


def grit_grain(rng: np.random.Generator, f_lo: float, f_hi: float, dur_ms: float = 3.2, q: float = 3.2) -> np.ndarray:
    """Tiny physical mineral/gravel grain click (noise-excited damped resonance, never pure sine)."""
    dur = max(0.0022, dur_ms * 0.001)
    n = max(16, int(round(dur * SR * 2.4)))
    exc = rng.standard_normal(n) * ad_env(n, 0.00035, dur * 0.42)
    band_part = butter_band(exc, f_lo, min(f_hi, 9200.0), order=2)
    f_res = rng.uniform(f_lo * 1.1, min(f_hi * 0.9, 7800.0))
    res_part = resonator(exc, f_res, q=q) * ad_env(n, 0.0004, dur * 0.55)
    return band_part * 0.65 + res_part * 0.45


def liquid_droplet(rng: np.random.Generator, f_center: float, dur_ms: float = 9.0) -> np.ndarray:
    """Realistic water bead / splash plip: resonant wet cavity excitation + tiny upward meniscus pop."""
    dur = max(0.004, dur_ms * 0.001)
    n = max(20, int(round(dur * SR * 2.3)))
    t = np.arange(n, dtype=np.float64) / SR
    exc = rng.standard_normal(n) * ad_env(n, 0.00045, dur * 0.36)
    wet_res = (
        resonator(exc, f_center, q=4.8) * 0.65
        + resonator(exc, min(f_center * 1.58, 7600.0), q=4.2) * 0.38
        + butter_band(exc, max(380.0, f_center * 0.6), min(f_center * 1.9, 7800.0), order=2) * 0.35
    )
    f_end = min(f_center * rng.uniform(1.14, 1.30), 5600.0)
    inst_f = f_center + (f_end - f_center) * np.clip(t / dur, 0.0, 1.0)
    ph = rng.uniform(0.0, 2.0 * np.pi) + 2.0 * np.pi * np.cumsum(inst_f) / SR
    meniscus = np.sin(ph) * ad_env(n, 0.0005, dur * 0.34)
    return wet_res * 0.78 + meniscus * 0.24


# ---------------------------------------------------------------------------
# 13 Surface Foley Synthesizers
# ---------------------------------------------------------------------------

def synth_grass(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    dur = {"sneak": 0.23, "walk": 0.26, "jog": 0.27, "sprint": 0.30}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.18, body_freq=106.0 + 5.0 * variant)

    # Soft meadow turf pad
    for t0, w in ((t_h, 1.0), (t_t, 0.72)):
        tn = int(0.044 * SR)
        turf = butter_band(rng.standard_normal(tn), 280.0, 1650.0, order=2)
        turf *= ad_env(tn, 0.0065 if gait == "sneak" else 0.0020, 0.013)
        add_at(buf, turf, t0, 0.32 * e * w)

    # Discrete crisp-soft leaf & grass-blade crinkles (short 2.5 - 9 ms organic micro-brushes, zero hiss)
    n_blades = {"sneak": 22, "walk": 34, "jog": 46, "sprint": 58}[gait]
    span = {"sneak": 0.082, "walk": 0.066, "jog": 0.062, "sprint": 0.078}[gait]
    att = 0.0032 if gait == "sneak" else 0.0009
    for i in range(n_blades):
        u = i / max(n_blades - 1, 1)
        g_dur = rng.uniform(0.0035, 0.011)
        gn = max(16, int(round(g_dur * SR)))
        lo = rng.uniform(850.0, 2250.0)
        hi = min(lo * rng.uniform(1.7, 2.4), 6200.0)
        blade = butter_band(rng.standard_normal(gn), lo, hi, order=2) * ad_env(gn, att, g_dur * 0.34)
        when = (t_h if rng.random() < 0.54 else t_t) + (u ** 1.2) * span * rng.uniform(0.60, 1.18)
        add_at(buf, blade, when, 0.145 * e * (1.0 - 0.48 * u) * rng.uniform(0.55, 1.35))

    # Gentle stem snaps inside the meadow turf
    n_stems = {"sneak": 2, "walk": 4, "jog": 7, "sprint": 10}[gait]
    for _ in range(n_stems):
        stem = grit_grain(rng, 1400.0, 4200.0, dur_ms=rng.uniform(1.8, 3.2), q=2.4)
        add_at(buf, stem, t_h + rng.uniform(0.003, 0.055), 0.065 * e)
    return butter_lp(buf, 7200.0, order=2)


def synth_steppe(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    dur = {"sneak": 0.24, "walk": 0.28, "jog": 0.29, "sprint": 0.33}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.34, body_freq=120.0 + 6.0 * variant)

    # Dry sun-baked earth + crisp golden straw rustle & dry stem snaps
    n_stalks = {"sneak": 16, "walk": 26, "jog": 34, "sprint": 46}[gait]
    span = {"sneak": 0.088, "walk": 0.074, "jog": 0.072, "sprint": 0.100}[gait]
    for i in range(n_stalks):
        u = i / max(n_stalks - 1, 1)
        s_dur = rng.uniform(0.005, 0.016)
        sn = int(s_dur * SR)
        lo = rng.uniform(1600.0, 3300.0)
        hi = min(lo * rng.uniform(1.7, 2.4), 8400.0)
        straw = butter_band(rng.standard_normal(sn), lo, hi, order=2)
        straw *= ad_env(sn, 0.0028 if gait == "sneak" else 0.0010, s_dur * 0.30)
        when = (t_h if rng.random() < 0.52 else t_t) + (u ** 1.1) * span * rng.uniform(0.6, 1.2)
        add_at(buf, straw, when, 0.12 * e * (1.0 - 0.40 * u) * rng.uniform(0.65, 1.3))

    n_snaps = {"sneak": 3, "walk": 6, "jog": 9, "sprint": 14}[gait]
    for _ in range(n_snaps):
        snap = grit_grain(rng, 2200.0, 6200.0, dur_ms=rng.uniform(1.8, 3.4), q=2.6)
        add_at(buf, snap, t_h + rng.uniform(0.004, 0.065), 0.085 * e * rng.uniform(0.55, 1.15))
    return butter_lp(buf, 8600.0, order=2)


def synth_path(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    dur = {"sneak": 0.22, "walk": 0.26, "jog": 0.28, "sprint": 0.33}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.52, body_freq=130.0 + 7.0 * variant)

    # Firm dirt-path leather step + fine sand/grit crunch
    for t0, w in ((t_h, 1.0), (t_t, 0.72)):
        cn = int(0.030 * SR)
        dirt = butter_band(rng.standard_normal(cn), 420.0, 2500.0, order=2)
        dirt *= ad_env(cn, 0.0042 if gait == "sneak" else 0.0012, 0.0085)
        add_at(buf, dirt, t0, 0.36 * e * w)

    n_grit = {"sneak": 5, "walk": 9, "jog": 14, "sprint": 20}[gait]
    tail = {"sneak": 0.052, "walk": 0.060, "jog": 0.082, "sprint": 0.125}[gait]
    for i in range(n_grit):
        u = (i / max(n_grit - 1, 1)) ** 1.35
        tick = grit_grain(rng, 1600.0, 4800.0, dur_ms=rng.uniform(2.0, 4.0), q=2.8)
        when = t_h + 0.002 + u * tail * rng.uniform(0.75, 1.15)
        add_at(buf, tick, when, 0.125 * e * (1.0 - 0.55 * u) * rng.uniform(0.55, 1.2))
    return butter_lp(buf, 8600.0, order=2)


def synth_slope(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    dur = {"sneak": 0.26, "walk": 0.31, "jog": 0.35, "sprint": 0.41}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.66, body_freq=138.0 + 7.0 * variant)

    for t0, w in ((t_h, 1.0), (t_t, 0.80)):
        cn = int(0.038 * SR)
        scuff = butter_band(rng.standard_normal(cn), 500.0, 3200.0, order=2)
        scuff *= ad_env(cn, 0.0038 if gait == "sneak" else 0.0011, 0.012)
        add_at(buf, scuff, t0, 0.36 * e * w)

    # Loose gravel & shale pebbles rolling down the slope
    n_stones = {"sneak": 9, "walk": 18, "jog": 26, "sprint": 36}[gait]
    span = {"sneak": 0.085, "walk": 0.125, "jog": 0.170, "sprint": 0.235}[gait]
    for i in range(n_stones):
        u = (i / max(n_stones - 1, 1)) ** 1.45
        pebble = grit_grain(rng, 1250.0, 4600.0, dur_ms=rng.uniform(2.4, 5.2), q=3.4)
        when = t_h + 0.003 + u * span * rng.uniform(0.78, 1.12)
        add_at(buf, pebble, when, 0.145 * e * (1.0 - 0.60 * u) * rng.uniform(0.5, 1.25))
    return butter_lp(buf, 8900.0, order=2)


def synth_stone(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    dur = {"sneak": 0.20, "walk": 0.23, "jog": 0.24, "sprint": 0.27}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.86, body_freq=155.0 + 9.0 * variant)

    # Noise-excited solid flagstone body + crisp leather sole contact
    stone_f = 285.0 + 22.0 * variant
    for idx, (t0, w) in enumerate(((t_h, 1.0), (t_t, 0.62 if gait != "sneak" else 0.42))):
        fm = 1.0 if idx == 0 else 1.15
        knock = foley_thud(rng, stone_f * fm, decay_s=0.0065, attack_s=0.0032 if gait == "sneak" else 0.0007, q=2.2)
        tn = int(0.016 * SR)
        slap = butter_band(rng.standard_normal(tn), 720.0, 3500.0, order=2)
        slap *= ad_env(tn, 0.0035 if gait == "sneak" else 0.0007, 0.0034)
        add_at(buf, knock, t0, 0.42 * e * w)
        add_at(buf, slap, t0, (0.20 if gait == "sneak" else 0.44) * e * w)

    n_dust = {"sneak": 1, "walk": 3, "jog": 5, "sprint": 8}[gait]
    for _ in range(n_dust):
        add_at(buf, grit_grain(rng, 2100.0, 5200.0, dur_ms=2.4, q=2.8), t_t + rng.uniform(0.003, 0.048), 0.07 * e)
    return butter_lp(buf, 8800.0, order=2)


def synth_mine_stone(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    dur = {"sneak": 0.26, "walk": 0.30, "jog": 0.32, "sprint": 0.36}[gait]
    dry = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(dry, rng, gait, hardness=0.90, body_freq=142.0 + 8.0 * variant)

    slate_f = 255.0 + 20.0 * variant
    for idx, (t0, w) in enumerate(((t_h, 1.0), (t_t, 0.65 if gait != "sneak" else 0.44))):
        fm = 1.0 if idx == 0 else 1.14
        knock = foley_thud(rng, slate_f * fm, decay_s=0.0075, attack_s=0.0030 if gait == "sneak" else 0.0007, q=2.5)
        tn = int(0.017 * SR)
        edge = butter_band(rng.standard_normal(tn), 680.0, 3900.0, order=2)
        edge *= ad_env(tn, 0.0032 if gait == "sneak" else 0.0007, 0.0036)
        add_at(dry, knock, t0, 0.44 * e * w)
        add_at(dry, edge, t0, (0.22 if gait == "sneak" else 0.46) * e * w)

    n_grit = {"sneak": 3, "walk": 6, "jog": 9, "sprint": 14}[gait]
    for i in range(n_grit):
        u = i / max(n_grit - 1, 1)
        add_at(dry, grit_grain(rng, 1800.0, 5000.0, dur_ms=2.8, q=3.2), t_h + 0.004 + u * 0.085 * rng.uniform(0.7, 1.2), 0.095 * e * (1.0 - 0.48 * u))

    # Diffuse cavern rock-wall early reflections
    out = dry.copy()
    refl = butter_band(dry, 200.0, 2500.0, order=2)
    for delay_s, gain in ((0.011, 0.15), (0.019, -0.11), (0.031, 0.075), (0.046, 0.045), (0.064, -0.025)):
        add_at(out, refl, delay_s + rng.uniform(-0.0012, 0.0012), gain)
    return butter_lp(out, 8800.0, order=2)


def synth_quartz(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    """Smooth hard sintered-quartz outcrop: crisp glassy-mineral step + noise-excited crystal sheen (never a xylophone ding)."""
    dur = {"sneak": 0.22, "walk": 0.25, "jog": 0.27, "sprint": 0.30}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.94, body_freq=165.0 + 8.0 * variant)

    crystal_formants = (
        (2650.0, 3950.0, 5450.0),
        (2820.0, 4180.0, 5720.0),
        (2520.0, 3780.0, 5200.0),
        (2940.0, 4340.0, 5920.0),
    )[variant % 4]

    for idx, (t0, w) in enumerate(((t_h, 1.0), (t_t, 0.62 if gait != "sneak" else 0.42))):
        fm = 1.0 if idx == 0 else 1.12
        mineral = foley_thud(rng, 320.0 * fm, decay_s=0.0062, attack_s=0.0030 if gait == "sneak" else 0.0006, q=2.4)
        tn = int(0.016 * SR)
        raw_tap = rng.standard_normal(tn)
        tap = butter_band(raw_tap, 900.0, 4600.0, order=2) * ad_env(tn, 0.0030 if gait == "sneak" else 0.0006, 0.0032)

        # Noise-excited crystalline mineral sheen (short 12 ms decay, zero musical bell pitch!)
        sn = int(0.032 * SR)
        exc = rng.standard_normal(sn) * ad_env(sn, 0.0012, 0.0045)
        sheen = (
            resonator(exc, crystal_formants[0] * fm, q=7.5) * 0.50
            + resonator(exc, crystal_formants[1] * fm, q=8.5) * 0.35
            + resonator(exc, crystal_formants[2] * fm, q=9.0) * 0.20
        ) * ad_env(sn, 0.0010, 0.011)

        add_at(buf, mineral, t0, 0.40 * e * w)
        add_at(buf, tap, t0, (0.22 if gait == "sneak" else 0.44) * e * w)
        add_at(buf, sheen, t0 + 0.0005, (0.09 if gait == "sneak" else 0.15) * e * w)

    # Crisp fine quartz-crystal grit under the sole
    n_grit = {"sneak": 3, "walk": 6, "jog": 10, "sprint": 15}[gait]
    for i in range(n_grit):
        u = (i / max(n_grit - 1, 1)) ** 1.3
        shard = grit_grain(rng, 2600.0, 6800.0, dur_ms=rng.uniform(2.0, 3.8), q=4.8)
        add_at(buf, shard, t_h + 0.002 + u * 0.075 * rng.uniform(0.7, 1.2), 0.10 * e * (1.0 - 0.52 * u))
    return butter_lp(buf, 9600.0, order=2)


def synth_sand(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    dur = {"sneak": 0.23, "walk": 0.26, "jog": 0.28, "sprint": 0.32}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    # Soft cushioned dune sink (zero hard knock)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.07, body_freq=94.0 + 4.0 * variant)

    # Compact sand-grain compression crunch (fine granular micro-bursts, never airy hiss)
    n_grains = {"sneak": 24, "walk": 36, "jog": 46, "sprint": 58}[gait]
    span = {"sneak": 0.075, "walk": 0.068, "jog": 0.066, "sprint": 0.088}[gait]
    att = 0.0028 if gait == "sneak" else 0.0009
    for i in range(n_grains):
        u = i / max(n_grains - 1, 1)
        g_dur = rng.uniform(0.0032, 0.0095)
        gn = max(16, int(round(g_dur * SR)))
        # Sweeps downward on foot sink (u < 0.45), then upward on toe push-off (u >= 0.45)
        lo = (1350.0 - 550.0 * (u / 0.45)) if u < 0.45 else (820.0 + 1100.0 * ((u - 0.45) / 0.55))
        lo *= rng.uniform(0.86, 1.16)
        hi = min(lo * rng.uniform(1.85, 2.55), 6400.0)
        grain = butter_band(rng.standard_normal(gn), lo, hi, order=2) * ad_env(gn, att, g_dur * 0.34)
        anchor = t_h if u < 0.48 else t_t
        local_u = (u / 0.48) if u < 0.48 else ((u - 0.48) / 0.52)
        when = anchor + (local_u ** 1.12) * span * 0.62 * rng.uniform(0.7, 1.18)
        add_at(buf, grain, when, 0.145 * e * (1.0 - 0.35 * local_u) * rng.uniform(0.65, 1.3))

    # Warm fine sand cushion bed underneath
    for t0, w, pd in ((t_h + 0.001, 1.0, 0.048), (t_t + 0.002, 0.78, 0.052)):
        pn = int(pd * SR)
        pad = butter_band(rng.standard_normal(pn), 520.0, 2650.0, order=2)
        pad *= ad_env(pn, 0.006 if gait == "sneak" else 0.0022, pd * 0.34)
        add_at(buf, pad, t0, 0.24 * e * w)
    return butter_lp(buf, 7400.0, order=2)


def synth_wood(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    """Dry hollow cabin floorboards & bridges: noise-excited damped wood formants (zero bongo sine!)."""
    dur = {"sneak": 0.21, "walk": 0.24, "jog": 0.25, "sprint": 0.28}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.68, body_freq=116.0 + 6.0 * variant)

    plank_f = (138.0, 156.0, 128.0, 168.0)[variant % 4] * rng.uniform(0.97, 1.03)
    for idx, (t0, w) in enumerate(((t_h, 1.0), (t_t, 0.62 if gait != "sneak" else 0.44))):
        fm = 1.0 if idx == 0 else 1.12
        wn = int(0.055 * SR)
        exc = rng.standard_normal(wn) * ad_env(wn, 0.0032 if gait == "sneak" else 0.0007, 0.0038)
        # Damped noise-driven wooden board cavity modes (decay ~ 9-13 ms, warm & woody)
        board = (
            resonator(exc, plank_f * fm, q=3.2) * 0.65
            + resonator(exc, plank_f * 2.18 * fm, q=3.8) * 0.48
            + resonator(exc, plank_f * 3.75 * fm, q=4.2) * 0.28
            + butter_band(exc, 420.0, 2300.0, order=2) * 0.55
        ) * ad_env(wn, 0.0028 if gait == "sneak" else 0.0007, 0.011)
        add_at(buf, board, t0, 0.52 * e * w)

    # Ultra-subtle wood grain micro-settle ticks on 2 variants
    if variant in (1, 3):
        for _ in range(2 if gait != "sneak" else 1):
            tick = grit_grain(rng, 450.0, 1650.0, dur_ms=2.2, q=3.5)
            add_at(buf, tick, t_t + rng.uniform(0.006, 0.032), 0.06 * e)
    return butter_lp(buf, 8000.0, order=2)


def synth_bed(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    """Loamy garden bed & tilled farm soil (`bed` & `field`): rich crumbly dark earth."""
    dur = {"sneak": 0.24, "walk": 0.28, "jog": 0.30, "sprint": 0.35}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.22, body_freq=98.0 + 5.0 * variant)

    for t0, w in ((t_h, 1.0), (t_t, 0.78)):
        ln = int(0.052 * SR)
        loam = butter_band(rng.standard_normal(ln), 260.0, 1650.0, order=2)
        loam *= ad_env(ln, 0.0052 if gait == "sneak" else 0.0018, 0.017)
        add_at(buf, loam, t0, 0.36 * e * w)

    n_clods = {"sneak": 12, "walk": 22, "jog": 30, "sprint": 42}[gait]
    span = {"sneak": 0.072, "walk": 0.082, "jog": 0.100, "sprint": 0.138}[gait]
    for i in range(n_clods):
        u = (i / max(n_clods - 1, 1)) ** 1.25
        cn = int(rng.uniform(0.006, 0.015) * SR)
        lo = rng.uniform(400.0, 1300.0)
        clod = butter_band(rng.standard_normal(cn), lo, lo * rng.uniform(1.8, 2.6), order=2)
        clod *= ad_env(cn, 0.0012, 0.0040)
        add_at(buf, clod, t_h + 0.003 + u * span * rng.uniform(0.7, 1.2), 0.125 * e * (1.0 - 0.5 * u) * rng.uniform(0.6, 1.25))
    return butter_lp(buf, 7400.0, order=2)


def synth_mud(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    """Wet heavy mud: damp earth compression + viscous noise-driven peel/squelch (no cartoon bloop)."""
    dur = {"sneak": 0.27, "walk": 0.32, "jog": 0.35, "sprint": 0.39}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)
    t_h, t_t, e = leather_sole_step(buf, rng, gait, hardness=0.14, body_freq=92.0 + 5.0 * variant)

    # Wet mud sink squish
    mn = int(0.058 * SR)
    slush = butter_band(rng.standard_normal(mn), 280.0, 2200.0, order=2)
    slush *= ad_env(mn, 0.0048 if gait == "sneak" else 0.0016, 0.019)
    add_at(buf, slush, t_h + 0.001, 0.38 * e)

    # Viscous boot-peel friction: clustered wet narrowband grains rising in frequency as sole lifts
    n_peel = {"sneak": 10, "walk": 15, "jog": 20, "sprint": 26}[gait]
    peel_span = {"sneak": 0.085, "walk": 0.075, "jog": 0.072, "sprint": 0.082}[gait]
    for i in range(n_peel):
        u = i / max(n_peel - 1, 1)
        f_mid = (380.0 + 18.0 * variant) + u * (950.0 if gait == "sneak" else 1550.0)
        gn = int(rng.uniform(0.006, 0.014) * SR)
        wet_grain = resonator(rng.standard_normal(gn), f_mid * rng.uniform(0.88, 1.14), q=3.2)
        wet_grain *= ad_env(gn, 0.0012, 0.0038)
        when = t_t + 0.004 + u * peel_span * rng.uniform(0.82, 1.12)
        bell = np.sin(np.pi * np.clip(u, 0.05, 0.95))
        add_at(buf, wet_grain, when, 0.16 * e * (0.45 + 0.75 * bell) * rng.uniform(0.65, 1.25))

    # Tiny wet mud splatter ticks
    n_splat = {"sneak": 4, "walk": 7, "jog": 12, "sprint": 18}[gait]
    s_span = {"sneak": 0.09, "walk": 0.11, "jog": 0.14, "sprint": 0.18}[gait]
    for i in range(n_splat):
        u = (i / max(n_splat - 1, 1)) ** 1.25
        drop = liquid_droplet(rng, rng.uniform(650.0, 2400.0), dur_ms=rng.uniform(4.5, 8.5))
        add_at(buf, drop, t_h + 0.006 + u * s_span * rng.uniform(0.75, 1.15), 0.12 * e * (1.0 - 0.48 * u))
    return butter_lp(buf, 7800.0, order=2)


def synth_shallow_water(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    """Ankle-deep river/shore wade: resonant liquid slosh + crisp falling water beads."""
    dur = {"sneak": 0.30, "walk": 0.36, "jog": 0.40, "sprint": 0.45}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)

    e = {"sneak": 0.44, "walk": 0.74, "jog": 0.94, "sprint": 1.12}[gait]
    t_entry = 0.0012
    t_lift = {"sneak": 0.050, "walk": 0.034, "jog": 0.022, "sprint": 0.020}[gait] + rng.uniform(-0.003, 0.004)

    # Soft submerged water displacement
    plunge = foley_thud(rng, 128.0 + 7.0 * variant, decay_s=0.016, attack_s=0.0070 if gait == "sneak" else 0.0015, q=1.5)
    add_at(buf, plunge, t_entry, 0.38 * e)

    # Staggered resonant liquid wavelets (gives unmistakable wet slosh body without flat noise)
    n_waves = {"sneak": 10, "walk": 16, "jog": 22, "sprint": 28}[gait]
    w_span = {"sneak": 0.10, "walk": 0.095, "jog": 0.090, "sprint": 0.105}[gait]
    for i in range(n_waves):
        u = i / max(n_waves - 1, 1)
        wn = int(rng.uniform(0.012, 0.026) * SR)
        raw = rng.standard_normal(wn) * ad_env(wn, 0.0035 if gait == "sneak" else 0.0012, 0.0075)
        f_liq = rng.uniform(360.0, 1450.0) * (0.85 + 0.55 * u)
        wavelet = resonator(raw, f_liq, q=3.4) * 0.70 + butter_band(raw, 420.0, 3200.0, order=2) * 0.35
        anchor = t_entry if i % 2 == 0 else t_lift
        when = anchor + (u ** 1.15) * w_span * rng.uniform(0.65, 1.18)
        add_at(buf, wavelet, when, 0.22 * e * (1.0 - 0.42 * u) * rng.uniform(0.6, 1.3))

    # Crisp falling water droplets & meniscus plips
    n_drops = {"sneak": 8, "walk": 16, "jog": 25, "sprint": 36}[gait]
    span = {"sneak": 0.15, "walk": 0.20, "jog": 0.25, "sprint": 0.31}[gait]
    for i in range(n_drops):
        u = (i / max(n_drops - 1, 1)) ** 1.35
        f_c = rng.uniform(520.0 + 520.0 * u, (1650.0 if gait == "sneak" else 2500.0) + 1700.0 * u)
        drop = liquid_droplet(rng, f_c, dur_ms=rng.uniform(5.5, 11.5) * (1.0 - 0.28 * u))
        when = t_entry + 0.004 + u * span * rng.uniform(0.78, 1.12)
        add_at(buf, drop, when, 0.18 * e * (1.0 - 0.50 * u) * rng.uniform(0.55, 1.25))
    return butter_lp(buf, 8400.0, order=2)


def synth_puddle(rng: np.random.Generator, gait: str, variant: int) -> np.ndarray:
    """Thin water-film slap + sparkling shallow droplet patter (standalone puddle & wet-ground layer)."""
    dur = {"sneak": 0.23, "walk": 0.28, "jog": 0.31, "sprint": 0.35}[gait]
    buf = np.zeros(int(dur * SR), dtype=np.float64)

    e = {"sneak": 0.42, "walk": 0.72, "jog": 0.92, "sprint": 1.10}[gait]
    t_hit = 0.0010
    t_toe = {"sneak": 0.036, "walk": 0.026, "jog": 0.015, "sprint": 0.017}[gait] + rng.uniform(-0.002, 0.003)

    # Wet-sole contact underneath
    wet_tap = foley_thud(rng, 175.0 + 10.0 * variant, decay_s=0.0080, attack_s=0.0042 if gait == "sneak" else 0.0009, q=1.8)
    add_at(buf, wet_tap, t_hit, 0.30 * e)

    # Resonant shallow water-film splash clusters (brighter & thinner than ankle-deep river wade)
    for idx, (t0, w) in enumerate(((t_hit, 1.0), (t_toe, 0.65 if gait != "sneak" else 0.45))):
        for k in range(4 if gait == "sneak" else 6):
            sn = int(rng.uniform(0.008, 0.018) * SR)
            raw = rng.standard_normal(sn) * ad_env(sn, 0.0028 if gait == "sneak" else 0.0007, 0.0052)
            f_film = rng.uniform(780.0, 2400.0 if gait == "sneak" else 3600.0)
            slap = resonator(raw, f_film, q=3.2) * 0.65 + butter_band(raw, 700.0, 4800.0, order=2) * 0.42
            add_at(buf, slap, t0 + k * rng.uniform(0.0025, 0.0055), (0.18 if gait == "sneak" else 0.28) * e * w * (1.0 - 0.11 * k))

    # Sparkling shallow droplet patter landing back around the boot
    n_drops = {"sneak": 7, "walk": 13, "jog": 20, "sprint": 28}[gait]
    span = {"sneak": 0.11, "walk": 0.15, "jog": 0.19, "sprint": 0.24}[gait]
    for i in range(n_drops):
        u = (i / max(n_drops - 1, 1)) ** 1.3
        f_drop = rng.uniform(900.0 + 480.0 * u, (2200.0 if gait == "sneak" else 3200.0) + 1600.0 * u)
        drop = liquid_droplet(rng, f_drop, dur_ms=rng.uniform(4.2, 8.2))
        when = t_hit + 0.003 + u * span * rng.uniform(0.75, 1.15)
        add_at(buf, drop, when, 0.175 * e * (1.0 - 0.50 * u) * rng.uniform(0.55, 1.25))
    return butter_lp(buf, 8800.0, order=2)


SURFACES: dict[str, Callable[[np.random.Generator, str, int], np.ndarray]] = {
    "grass": synth_grass,
    "steppe": synth_steppe,
    "path": synth_path,
    "slope": synth_slope,
    "stone": synth_stone,
    "mine_stone": synth_mine_stone,
    "quartz": synth_quartz,
    "sand": synth_sand,
    "wood": synth_wood,
    "bed": synth_bed,
    "mud": synth_mud,
    "shallow_water": synth_shallow_water,
    "puddle": synth_puddle,
}

TARGET_RMS_DB: dict[str, float] = {
    "sneak": -23.5,
    "walk": -18.5,
    "jog": -15.8,
    "sprint": -13.5,
}

PEAK_CEILING: dict[str, float] = {
    "sneak": 0.42,
    "walk": 0.68,
    "jog": 0.82,
    "sprint": 0.93,
}


def master_step(sig: np.ndarray, gait: str) -> np.ndarray:
    sig = butter_hp(sig, 40.0, order=2)

    win = min(sig.size, int(0.095 * SR))
    active_rms = float(np.sqrt(np.mean(sig[:win] ** 2) + 1e-12))
    target_rms = 10.0 ** (TARGET_RMS_DB[gait] / 20.0)
    sig = sig * (target_rms / active_rms)

    ceil = PEAK_CEILING[gait]
    peak = float(np.max(np.abs(sig)) + 1e-12)
    if peak > ceil * 0.80:
        knee = ceil * 0.80
        above = np.maximum(np.abs(sig) - knee, 0.0)
        span = max(ceil - knee, 1e-4)
        sig = np.where(
            np.abs(sig) <= knee,
            sig,
            np.sign(sig) * (knee + span * np.tanh(above / span)),
        )

    fade_n = min(int(0.012 * SR), sig.size // 4)
    if fade_n > 0:
        sig[-fade_n:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, fade_n))
    sig[0] = 0.0
    sig[-1] = 0.0
    return sig


def write_wav(path: Path, sig: np.ndarray) -> None:
    pcm = np.clip(np.round(sig * 32767.0), -32767, 32767).astype(np.int16)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())


def cleanup_obsolete_mp3s() -> int:
    removed = 0
    for p in list(OUT_DIR.glob("*.mp3")) + list(OUT_DIR.glob("*.mp3.import")):
        if p.name.startswith("swim_"):
            continue
        p.unlink()
        removed += 1
    return removed


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    removed = cleanup_obsolete_mp3s()
    total = 0
    for s_idx, (surface, fn) in enumerate(SURFACES.items()):
        for g_idx, gait in enumerate(GAITS):
            for v in range(1, VARIANTS + 1):
                seed = 910_000 + s_idx * 1000 + g_idx * 100 + v * 17
                rng = np.random.default_rng(seed)
                raw = fn(rng, gait, v - 1)
                mastered = master_step(raw, gait)
                out_path = OUT_DIR / f"{surface}_{gait}_{v}.wav"
                write_wav(out_path, mastered)
                total += 1
    print(f"Generated {total} footstep WAVs in {OUT_DIR} (removed {removed} obsolete step MP3/import files).")


if __name__ == "__main__":
    main()
