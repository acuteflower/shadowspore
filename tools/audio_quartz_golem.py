#!/usr/bin/env python3
"""Procedural SFX generator for the Sonnenquarz-Öde Quarzwächter (quartz_golem):
- assets/audio/golem/awaken.wav      (levitating sandstone blocks snap together + turquoise-gold crystal chime)
- assets/audio/golem/charge.wav      (singing sun-quartz resonance hum during windup)
- assets/audio/golem/shard_cast.wav  (three faceted quartz spikes crystallizing and launching)
- assets/audio/golem/shock_erupt.wav (subterranean sandstone thud + erupting quartz spires)
- assets/audio/golem/blade_slash.wav (rapid arm-crystal sword growth + razor quartz slash)
- assets/audio/golem/death.wav       (snapping arcane tether + tumbling sandstone & crystal shards)
"""
import math
import os
import wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "golem")
SR = 44100


def save_wav(name: str, samples: np.ndarray) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    peak = float(np.max(np.abs(samples)))
    if peak > 1e-6:
        samples = samples / peak * 0.80
    pcm = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())
    print(f"wrote assets/audio/golem/{name} ({len(pcm)} samples)")


def _lowpass_noise(rng: np.random.Generator, length: int, width: int) -> np.ndarray:
    raw = rng.normal(0.0, 1.0, length)
    kernel = np.hanning(width)
    kernel /= max(kernel.sum(), 1e-9)
    return np.convolve(raw, kernel, mode="same")


def gen_awaken() -> np.ndarray:
    dur = 0.64
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    rng = np.random.default_rng(8101)
    sig = np.zeros_like(t)
    # Three levitating sandstone clacks snapping into place
    for onset, freq, amp in [(0.02, 165.0, 0.42), (0.11, 215.0, 0.38), (0.21, 275.0, 0.46)]:
        dt = np.maximum(t - onset, 0.0)
        gate = np.where(t >= onset, np.minimum(dt / 0.004, 1.0), 0.0)
        clack = _lowpass_noise(rng, len(t), 28) * np.exp(-dt * 42.0) * gate * amp
        thump = np.sin(2.0 * math.pi * freq * dt) * np.exp(-dt * 28.0) * gate * (amp * 0.85)
        sig += clack + thump
    # Rising turquoise-amber sun-quartz chord (D5 -> A5 -> F#6)
    for onset, freq, amp in [(0.14, 587.33, 0.34), (0.22, 880.0, 0.30), (0.30, 1479.98, 0.24)]:
        dt = np.maximum(t - onset, 0.0)
        gate = np.where(t >= onset, np.minimum(dt / 0.012, 1.0), 0.0)
        bell = (0.72 * np.sin(2.0 * math.pi * freq * dt) + 0.28 * np.sin(2.0 * math.pi * freq * 2.41 * dt))
        sig += bell * gate * np.exp(-dt * 5.8) * amp
    return sig


def gen_charge() -> np.ndarray:
    dur = 0.62
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    rng = np.random.default_rng(8102)
    env = np.minimum(t / 0.08, 1.0) * np.minimum((dur - t) / 0.07, 1.0)
    # Rising crystalline harmonic hum
    f0 = 440.0 * (1.0 + 0.42 * (t / dur) ** 1.35)
    ph0 = 2.0 * math.pi * np.cumsum(f0) / SR
    ph1 = 2.0 * math.pi * np.cumsum(f0 * 1.5) / SR
    ph2 = 2.0 * math.pi * np.cumsum(f0 * 2.75) / SR
    hum = (0.50 * np.sin(ph0) + 0.32 * np.sin(ph1) + 0.18 * np.sin(ph2)) * env
    grit = _lowpass_noise(rng, len(t), 42) * np.sin(2.0 * math.pi * 1950.0 * t) * env * 0.14
    return hum + grit


def gen_shard_cast() -> np.ndarray:
    dur = 0.44
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    rng = np.random.default_rng(8103)
    sig = np.zeros_like(t)
    # Rapid 3-shard crystalline launch pings + airy sand-glass whoosh
    for onset, freq, amp in [(0.00, 1174.66, 0.44), (0.045, 1396.91, 0.38), (0.09, 1760.0, 0.34)]:
        dt = np.maximum(t - onset, 0.0)
        gate = np.where(t >= onset, np.minimum(dt / 0.003, 1.0), 0.0)
        sweep = freq * (1.0 - 0.22 * np.minimum(dt / 0.18, 1.0))
        ph = 2.0 * math.pi * np.cumsum(sweep) / SR
        ping = (0.70 * np.sin(ph) + 0.30 * np.sin(ph * 2.13)) * np.exp(-dt * 12.5) * gate * amp
        whoosh = rng.normal(0.0, 1.0, len(t)) * np.sin(2.0 * math.pi * 2900.0 * dt) * np.exp(-dt * 22.0) * gate * 0.16
        sig += ping + whoosh
    return sig


def gen_shock_erupt() -> np.ndarray:
    dur = 0.68
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    rng = np.random.default_rng(8104)
    attack = np.minimum(t / 0.008, 1.0)
    # Deep desert sandstone impact + cracking stone + upward quartz spire ring
    f_sub = 118.0 * np.exp(-t * 5.2) + 46.0
    ph_sub = 2.0 * math.pi * np.cumsum(f_sub) / SR
    sub = 0.62 * np.sin(ph_sub) * np.exp(-t * 5.8) * attack
    crunch = _lowpass_noise(rng, len(t), 22) * np.exp(-t * 11.0) * attack * 0.52
    spires = np.zeros_like(t)
    for onset, freq, amp in [(0.02, 659.25, 0.28), (0.055, 987.77, 0.25), (0.095, 1479.98, 0.22)]:
        dt = np.maximum(t - onset, 0.0)
        gate = np.where(t >= onset, np.minimum(dt / 0.005, 1.0), 0.0)
        spires += np.sin(2.0 * math.pi * freq * dt) * np.exp(-dt * 7.8) * gate * amp
    return sub + crunch + spires


def gen_blade_slash() -> np.ndarray:
    dur = 0.40
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    rng = np.random.default_rng(8105)
    attack = np.minimum(t / 0.005, 1.0)
    # Sharp crystal blade flash + sweeping resonant arc + shatter tail
    f_blade = 1567.98 * (1.0 - 0.36 * np.minimum(t / 0.24, 1.0))
    ph = 2.0 * math.pi * np.cumsum(f_blade) / SR
    ring = (0.65 * np.sin(ph) + 0.35 * np.sin(ph * 1.5)) * np.exp(-t * 9.5) * attack * 0.48
    whoosh_env = np.sin(math.pi * np.minimum(t / 0.24, 1.0)) ** 1.4 * np.where(t < 0.24, 1.0, 0.0)
    whoosh = _lowpass_noise(rng, len(t), 12) * whoosh_env * 0.58
    dt_sh = np.maximum(t - 0.19, 0.0)
    gate_sh = np.where(t >= 0.19, 1.0, 0.0)
    shatter = rng.normal(0.0, 1.0, len(t)) * np.sin(2.0 * math.pi * 3400.0 * dt_sh) * np.exp(-dt_sh * 24.0) * gate_sh * 0.20
    return ring + whoosh + shatter


def gen_death() -> np.ndarray:
    dur = 0.96
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    rng = np.random.default_rng(8106)
    attack = np.minimum(t / 0.008, 1.0)
    # Snapping arcane tether (descending crystal chord) + tumbling sandstone blocks & shards
    f_snap = 987.77 * np.exp(-t * 2.8)
    ph_snap = 2.0 * math.pi * np.cumsum(f_snap) / SR
    tether = (0.55 * np.sin(ph_snap) + 0.30 * np.sin(ph_snap * 1.498)) * np.exp(-t * 4.2) * attack * 0.42
    tumble = np.zeros_like(t)
    for onset, freq, amp in [
        (0.06, 175.0, 0.38),
        (0.16, 142.0, 0.34),
        (0.29, 198.0, 0.30),
        (0.43, 128.0, 0.26),
        (0.58, 162.0, 0.18),
    ]:
        dt = np.maximum(t - onset, 0.0)
        gate = np.where(t >= onset, np.minimum(dt / 0.004, 1.0), 0.0)
        stone = _lowpass_noise(rng, len(t), 26) * np.exp(-dt * 32.0) * gate * amp
        thud = np.sin(2.0 * math.pi * freq * dt) * np.exp(-dt * 22.0) * gate * (amp * 0.75)
        chime = np.sin(2.0 * math.pi * (freq * 7.2) * dt) * np.exp(-dt * 18.0) * gate * (amp * 0.35)
        tumble += stone + thud + chime
    return tether + tumble


def main() -> None:
    save_wav("awaken.wav", gen_awaken())
    save_wav("charge.wav", gen_charge())
    save_wav("shard_cast.wav", gen_shard_cast())
    save_wav("shock_erupt.wav", gen_shock_erupt())
    save_wav("blade_slash.wav", gen_blade_slash())
    save_wav("death.wav", gen_death())


if __name__ == "__main__":
    main()
