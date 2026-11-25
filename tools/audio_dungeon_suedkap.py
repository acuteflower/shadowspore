#!/usr/bin/env python3
"""Procedural audio generator for Shadowspore Dungeon #1 (Die Gezeitenkammern von Sturmhafen)
and Lost-Ark Combat SFX (Klangkonter, Taumelbruch, Gezeitenglocke, Fluttor, Springflut, Vorgath).
Pure Python stdlib + math/wave/struct -> 16-bit 22050 Hz mono WAVs under assets/audio/dungeon/.
"""
from __future__ import annotations

import math
import pathlib
import random
import struct
import wave

OUT_DIR = pathlib.Path(__file__).resolve().parents[1] / "assets" / "audio" / "dungeon"
SR = 22050


def write_wav(name: str, samples: list[float]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    peak = max((abs(s) for s in samples), default=1.0)
    scale = 0.88 / max(peak, 1e-6)
    path = OUT_DIR / name
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        raw = bytearray()
        for s in samples:
            v = max(-32767, min(32767, int(round(s * scale * 32767.0))))
            raw.extend(struct.pack("<h", v))
        wf.writeframes(bytes(raw))
    print(f"[audio_dungeon_suedkap] wrote {name} ({len(samples) / SR:.2f}s)")


def env_ad(t: float, a: float, dur: float, exp_p: float = 1.6) -> float:
    if t < a:
        return t / max(a, 1e-5)
    u = max(0.0, 1.0 - (t - a) / max(dur - a, 1e-5))
    return u ** exp_p


def make_counter_flash() -> None:
    """Crisp crystalline ice-blue warning chime (0.38s) before a counterable attack."""
    dur = 0.38
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        e = env_ad(t, 0.008, dur, 2.2)
        f = 880.0 + 440.0 * min(1.0, t / 0.14)
        s = math.sin(2 * math.pi * f * t) * 0.55 + math.sin(2 * math.pi * f * 1.5 * t) * 0.32 + math.sin(2 * math.pi * 2200.0 * t) * 0.18 * env_ad(t, 0.004, 0.16, 2.0)
        out.append(s * e)
    write_wav("counter_flash.wav", out)


def make_counter_hit() -> None:
    """Punchy metallic Lost-Ark Klangkonter bell-clang + sub thump (0.55s)."""
    dur = 0.55
    n = int(SR * dur)
    rng = random.Random(101)
    out = []
    for i in range(n):
        t = i / SR
        sub = math.sin(2 * math.pi * (120.0 * math.exp(-t * 6.0) + 46.0) * t) * env_ad(t, 0.003, 0.28, 2.0) * 0.75
        clang = (
            math.sin(2 * math.pi * 660.0 * t) * 0.40
            + math.sin(2 * math.pi * 1188.0 * t) * 0.32
            + math.sin(2 * math.pi * 1760.0 * t) * 0.25
        ) * env_ad(t, 0.002, dur, 2.4)
        burst = (rng.random() * 2.0 - 1.0) * env_ad(t, 0.001, 0.055, 2.5) * 0.38
        out.append(sub + clang + burst)
    write_wav("counter_hit.wav", out)


def make_stagger_break() -> None:
    """Resonant golden shield-shatter + triumphant Steinsetzer harmonic chord (0.72s)."""
    dur = 0.72
    n = int(SR * dur)
    rng = random.Random(202)
    out = []
    freqs = (329.6, 493.9, 659.3, 987.8)
    for i in range(n):
        t = i / SR
        thud = math.sin(2 * math.pi * (95.0 * math.exp(-t * 5.0) + 38.0) * t) * env_ad(t, 0.004, 0.32, 1.8) * 0.7
        chord = sum(math.sin(2 * math.pi * f * t) * (0.28 / (1.0 + k * 0.3)) for k, f in enumerate(freqs)) * env_ad(t, 0.012, dur, 1.7)
        shatter = (rng.random() * 2.0 - 1.0) * env_ad(t, 0.002, 0.14, 2.2) * 0.42
        out.append(thud + chord + shatter)
    write_wav("stagger_break.wav", out)


def make_tide_bell() -> None:
    """Deep bronze harbor Tide Bell toll with shimmering turquoise overtones (1.8s)."""
    dur = 1.80
    n = int(SR * dur)
    partials = [(196.0, 0.65, 1.4), (392.0, 0.35, 1.9), (470.0, 0.28, 2.3), (588.0, 0.22, 2.6), (880.0, 0.14, 3.2)]
    out = []
    for i in range(n):
        t = i / SR
        s = 0.0
        for f, amp, dec in partials:
            s += math.sin(2 * math.pi * f * t) * amp * math.exp(-t * dec)
        strike = math.sin(2 * math.pi * 1120.0 * t) * math.exp(-t * 28.0) * 0.35
        out.append((s + strike) * min(1.0, t / 0.008))
    write_wav("tide_bell.wav", out)


def make_floodgate_open() -> None:
    """Heavy bronze winch chain & rumbling basalt floodgate raising (1.4s)."""
    dur = 1.40
    n = int(SR * dur)
    rng = random.Random(303)
    lp = 0.0
    out = []
    for i in range(n):
        t = i / SR
        noise = rng.random() * 2.0 - 1.0
        lp = lp * 0.92 + noise * 0.08
        rumble = (lp * 1.4 + math.sin(2 * math.pi * (52.0 + 18.0 * t) * t) * 0.35) * env_ad(t, 0.08, dur, 1.2)
        click_phase = (t * 9.5) % 1.0
        chain = math.sin(2 * math.pi * 780.0 * t) * math.exp(-click_phase * 28.0) * 0.24 * (1.0 - t / dur * 0.4)
        out.append(rumble + chain)
    write_wav("floodgate_open.wav", out)


def make_spring_tide() -> None:
    """Roaring ocean wave crashing through the northern sluice gate (1.6s)."""
    dur = 1.60
    n = int(SR * dur)
    rng = random.Random(404)
    lp1, lp2 = 0.0, 0.0
    out = []
    for i in range(n):
        t = i / SR
        u = t / dur
        swell = math.sin(u * math.pi) ** 1.2
        white = rng.random() * 2.0 - 1.0
        lp1 = lp1 * 0.88 + white * 0.12
        lp2 = lp2 * 0.965 + white * 0.035
        sub = math.sin(2 * math.pi * (44.0 + 16.0 * swell) * t) * 0.32 * swell
        out.append((lp1 * 0.65 + lp2 * 0.95) * swell + sub)
    write_wav("spring_tide.wav", out)


def make_vorgath_slam() -> None:
    """Heavy anchor slam + wet splash (0.48s)."""
    dur = 0.48
    n = int(SR * dur)
    rng = random.Random(505)
    lp = 0.0
    out = []
    for i in range(n):
        t = i / SR
        white = rng.random() * 2.0 - 1.0
        lp = lp * 0.82 + white * 0.18
        impact = math.sin(2 * math.pi * (115.0 * math.exp(-t * 9.0) + 34.0) * t) * env_ad(t, 0.002, 0.34, 2.1)
        metal = math.sin(2 * math.pi * 410.0 * t) * math.exp(-t * 14.0) * 0.28
        splash = lp * env_ad(t, 0.02, dur, 1.8) * 0.42
        out.append(impact * 0.85 + metal + splash)
    write_wav("vorgath_slam.wav", out)


def make_victory_fanfare() -> None:
    """Steinsetzer triumphant arpeggio chime on dungeon clear (1.35s)."""
    dur = 1.35
    n = int(SR * dur)
    notes = [(0.0, 392.0), (0.12, 493.88), (0.24, 587.33), (0.38, 783.99)]
    out = []
    for i in range(n):
        t = i / SR
        s = 0.0
        for onset, freq in notes:
            if t >= onset:
                dt = t - onset
                e = env_ad(dt, 0.01, max(0.35, dur - onset), 1.6)
                s += (math.sin(2 * math.pi * freq * dt) * 0.55 + math.sin(2 * math.pi * freq * 2.0 * dt) * 0.20) * e
        out.append(s)
    write_wav("victory_fanfare.wav", out)


def main() -> None:
    make_counter_flash()
    make_counter_hit()
    make_stagger_break()
    make_tide_bell()
    make_floodgate_open()
    make_spring_tide()
    make_vorgath_slam()
    make_victory_fanfare()


if __name__ == "__main__":
    main()
