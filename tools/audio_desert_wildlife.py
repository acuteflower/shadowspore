#!/usr/bin/env python3
"""Deterministic procedural acoustic calls for the 6 Sonnenquarz-Öde wildlife species (numpy + stdlib).
Writes:
  assets/audio/sfx/{oryx_snort,fennec_yip,jerboa_drum,falcon_cry}.wav
  assets/audio/wildlife/{desert_falcon_0,desert_falcon_1}.wav
"""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / 'assets/audio/sfx'
WILD_DIR = ROOT / 'assets/audio/wildlife'
SFX_DIR.mkdir(parents=True, exist_ok=True)
WILD_DIR.mkdir(parents=True, exist_ok=True)
RATE = 22050


def save_wav(path: Path, signal: np.ndarray, peak: float = 0.48) -> None:
    sig = np.asarray(signal, dtype=np.float64)
    sig = sig - np.mean(sig)
    mx = float(np.max(np.abs(sig)))
    if mx > 1e-8:
        sig = sig / mx * peak
    pcm = np.clip(sig * 32767.0, -32767.0, 32767.0).astype(np.int16)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def lowpass(x: np.ndarray, k: int) -> np.ndarray:
    if k <= 1:
        return x
    return np.convolve(x, np.ones(k) / k, mode='same')


def formant_voice(
    f: np.ndarray,
    formants: list[float],
    rng: np.random.Generator,
    breath: float = 0.08,
    harmonics: int = 16,
) -> np.ndarray:
    phase = np.cumsum(f) * (2.0 * np.pi / RATE)
    sig = np.zeros_like(f, dtype=np.float64)
    base = float(np.mean(f))
    for h in range(1, harmonics + 1):
        weight = 0.05 / h + sum(
            np.exp(-0.5 * ((h * base - fm) / (fm * 0.23)) ** 2) for fm in formants
        ) / (1.0 + h * 0.17)
        sig += weight * np.sin(phase * h)
    if breath > 0.0:
        n = rng.standard_normal(len(f))
        sig += breath * (lowpass(n, 3) - lowpass(n, 24))
    return sig


def make_oryx_snort(rng: np.random.Generator) -> np.ndarray:
    """Dry nasal antelope warning snort + low chest resonance."""
    dur = 0.46
    t = np.arange(int(RATE * dur)) / RATE
    u = t / dur
    n = rng.standard_normal(len(t))
    flutter = 0.72 + 0.28 * np.sin(2.0 * np.pi * 38.0 * t)
    snort = (lowpass(n, 3) - lowpass(n, 18)) * flutter
    chest = formant_voice(122.0 - 28.0 * u, [310.0, 820.0, 1460.0], rng, breath=0.06) * 0.58
    env = np.minimum(1.0, u * 26.0) * np.exp(-3.4 * u) * (np.sin(np.pi * u) ** 0.35)
    return lowpass((snort + chest) * env, 3)


def make_fennec_yip(rng: np.random.Generator) -> np.ndarray:
    """Delicate high desert-fox two-syllable 'yip-churr'."""
    out = np.zeros(int(RATE * 0.44))
    for start, dur, f0, drop in ((0.02, 0.13, 980.0, 220.0), (0.19, 0.18, 820.0, 260.0)):
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f = f0 + 130.0 * np.sin(np.pi * np.clip(u * 1.3, 0.0, 1.0)) - drop * u
        f += 14.0 * np.sin(2.0 * np.pi * 46.0 * t)
        v = formant_voice(f, [1350.0, 2650.0, 4100.0], rng, breath=0.14, harmonics=12)
        env = np.minimum(1.0, u * 22.0) * np.exp(-3.2 * u) * np.sin(np.pi * u) ** 0.55
        idx = int(start * RATE)
        seg = lowpass(v * env, 2)
        out[idx:idx + len(seg)] += seg[:len(out) - idx]
    return out


def make_jerboa_drum(rng: np.random.Generator) -> np.ndarray:
    """Rapid muffled hind-foot sand-drumming alarm (three quick dry thumps in fine sand)."""
    out = np.zeros(int(RATE * 0.34))
    for start, amp in ((0.02, 0.85), (0.10, 1.0), (0.19, 0.78)):
        dur = 0.055
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        thump = np.sin(2.0 * np.pi * (145.0 - 65.0 * u) * t) * np.exp(-38.0 * t)
        grain = (lowpass(rng.standard_normal(len(t)), 5) - lowpass(rng.standard_normal(len(t)), 26)) * np.exp(-28.0 * t) * 0.35
        seg = lowpass((thump + grain) * amp, 3)
        idx = int(start * RATE)
        out[idx:idx + len(seg)] += seg[:len(out) - idx]
    return out


def make_falcon_cry(rng: np.random.Generator, notes: int = 3, base_hz: float = 1980.0) -> np.ndarray:
    """Airy, high-altitude Lanner falcon 'klii-klii-klii' cry over open desert."""
    total = 0.18 + notes * 0.17
    out = np.zeros(int(RATE * total))
    for i in range(notes):
        start = 0.03 + i * 0.155
        dur = 0.125
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f0 = base_hz * (1.0 - 0.04 * i)
        f = f0 + 210.0 * np.sin(np.pi * np.clip(u * 1.4, 0.0, 1.0)) - 320.0 * (u ** 1.3)
        phase = np.cumsum(f) * (2.0 * np.pi / RATE)
        tone = 0.72 * np.sin(phase) + 0.24 * np.sin(2.0 * phase) + 0.09 * np.sin(3.0 * phase)
        air = (lowpass(rng.standard_normal(len(t)), 2) - lowpass(rng.standard_normal(len(t)), 14)) * 0.12
        env = np.minimum(1.0, u * 18.0) * np.exp(-2.6 * u) * np.sin(np.pi * u) ** 0.65
        idx = int(start * RATE)
        seg = (tone + air) * env
        out[idx:idx + len(seg)] += seg[:len(out) - idx]
    return out


def main() -> None:
    rng = np.random.default_rng(20261113)
    save_wav(SFX_DIR / 'oryx_snort.wav', make_oryx_snort(rng), peak=0.46)
    save_wav(SFX_DIR / 'fennec_yip.wav', make_fennec_yip(rng), peak=0.40)
    save_wav(SFX_DIR / 'jerboa_drum.wav', make_jerboa_drum(rng), peak=0.44)
    cry_a = make_falcon_cry(rng, notes=3, base_hz=1980.0)
    cry_b = make_falcon_cry(rng, notes=2, base_hz=1840.0)
    save_wav(SFX_DIR / 'falcon_cry.wav', cry_a, peak=0.38)
    save_wav(WILD_DIR / 'desert_falcon_0.wav', cry_a, peak=0.38)
    save_wav(WILD_DIR / 'desert_falcon_1.wav', cry_b, peak=0.36)
    print('Desert wildlife audio generated.')


if __name__ == '__main__':
    main()
