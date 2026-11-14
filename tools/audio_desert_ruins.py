#!/usr/bin/env python3
"""Procedural SFX generator for Sonnenquarz-Öde active ruin magic:
- assets/audio/sfx/conduit_pulse.wav (spark racing along a stone light conduit)
- assets/audio/sfx/prism_ring.wav (expanding prismatic resonance ring from an obelisk)
- assets/audio/sfx/seal_awake.wav (ancient quartz seal locking open in the sand)
"""
import math
import os
import wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
SR = 44100


def save_wav(name: str, samples: np.ndarray) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    peak = float(np.max(np.abs(samples)))
    if peak > 1e-6:
        samples = samples / peak * 0.78
    pcm = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())
    print(f"wrote {name} ({len(pcm)} samples)")


def gen_conduit_pulse() -> np.ndarray:
    dur = 0.42
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    env = np.exp(-t * 8.5) * np.minimum(t / 0.012, 1.0)
    # Rising crystalline quartz glissando + airy sand-glass shimmer
    f0 = 587.33 * (1.0 + 0.48 * (t / dur))
    phase0 = 2.0 * math.pi * np.cumsum(f0) / SR
    phase1 = 2.0 * math.pi * np.cumsum(f0 * 1.5) / SR
    phase2 = 2.0 * math.pi * np.cumsum(f0 * 2.5) / SR
    tone = 0.58 * np.sin(phase0) + 0.30 * np.sin(phase1) + 0.16 * np.sin(phase2)
    rng = np.random.default_rng(4201)
    shimmer = rng.normal(0.0, 1.0, len(t))
    # Simple resonant high-band sparkle via AM
    spark = shimmer * np.sin(2.0 * math.pi * 2650.0 * t) * np.exp(-t * 13.0) * 0.16
    return tone * env + spark


def gen_prism_ring() -> np.ndarray:
    dur = 0.58
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    attack = np.minimum(t / 0.018, 1.0)
    env = attack * np.exp(-t * 5.4)
    # Prismatic open fifth + major 9th crystal chord (D5, A5, E6, F#6)
    freqs = [587.33, 880.0, 1318.51, 1479.98]
    amps = [0.46, 0.34, 0.22, 0.14]
    sig = np.zeros_like(t)
    for i, (f, a) in enumerate(zip(freqs, amps)):
        vib = 1.0 + 0.004 * np.sin(2.0 * math.pi * (6.5 + i * 1.3) * t)
        ph = 2.0 * math.pi * np.cumsum(f * vib) / SR
        sig += a * np.sin(ph) * np.exp(-t * (1.2 * i))
    sub = 0.24 * np.sin(2.0 * math.pi * 146.83 * t) * np.exp(-t * 9.0) * attack
    return sig * env + sub


def gen_seal_awake() -> np.ndarray:
    dur = 0.92
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    attack = np.minimum(t / 0.035, 1.0)
    # Warm stone rumble + rising quartz bell triad (D4 -> A4 -> F#5 -> D6)
    rng = np.random.default_rng(7719)
    rumble_raw = rng.normal(0.0, 1.0, len(t))
    kernel = np.hanning(96)
    kernel /= kernel.sum()
    rumble = np.convolve(rumble_raw, kernel, mode="same") * np.exp(-t * 4.8) * attack * 0.32
    notes = [
        (0.00, 293.66, 0.42, 3.2),
        (0.08, 440.00, 0.36, 3.4),
        (0.17, 739.99, 0.30, 3.8),
        (0.26, 1174.66, 0.26, 4.2),
    ]
    chime = np.zeros_like(t)
    for start, freq, amp, decay in notes:
        dt = np.maximum(t - start, 0.0)
        gate = np.where(t >= start, np.minimum(dt / 0.014, 1.0), 0.0)
        chime += amp * gate * np.exp(-dt * decay) * (
            0.75 * np.sin(2.0 * math.pi * freq * dt) + 0.25 * np.sin(2.0 * math.pi * freq * 2.0 * dt)
        )
    return rumble + chime


def main() -> None:
    save_wav("conduit_pulse.wav", gen_conduit_pulse())
    save_wav("prism_ring.wav", gen_prism_ring())
    save_wav("seal_awake.wav", gen_seal_awake())


if __name__ == "__main__":
    main()
