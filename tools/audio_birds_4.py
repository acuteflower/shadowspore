#!/usr/bin/env python3
"""Deterministic procedural acoustic calls & drumming SFX for the 4 new Hauptwelt bird species:
  - Woodpecker (Buntspecht / Schwarzspecht / Grünspecht): hollow-trunk drum roll + 'Kix!' & 'Klü-klü-klü'
  - Mallard Duck (Stockente): nasal hen decrescendo quack series + drake 'raeb-raeb'
  - Eurasian Jay (Eichelhäher): rasping 'Räätsch!' sentinel alarm shriek + woodland call
  - European Robin (Rotkehlchen): liquid silvery cascading warble + 'tick-tick' call
"""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "assets/audio/sfx"
WILD_DIR = ROOT / "assets/audio/wildlife"
SFX_DIR.mkdir(parents=True, exist_ok=True)
WILD_DIR.mkdir(parents=True, exist_ok=True)
RATE = 22050


def save_wav(path: Path, signal: np.ndarray, peak: float = 0.50) -> None:
    sig = np.asarray(signal, dtype=np.float64)
    sig = sig - np.mean(sig)
    mx = float(np.max(np.abs(sig)))
    if mx > 1e-8:
        sig = sig / mx * peak
    pcm = np.clip(sig * 32767.0, -32767.0, 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def lowpass(x: np.ndarray, k: int) -> np.ndarray:
    if k <= 1:
        return x
    return np.convolve(x, np.ones(k) / k, mode="same")


def make_woodpecker_drum(rng: np.random.Generator) -> np.ndarray:
    """Authentic resonant spruce-trunk drumming roll (~13 strikes in 0.68s, hollow wood modes)."""
    out = np.zeros(int(RATE * 0.78))
    t_cursor = 0.025
    n_strikes = 13
    for i in range(n_strikes):
        dur = 0.055
        t = np.arange(int(RATE * dur)) / RATE
        # Hollow deadwood cavity resonances + crisp beak click transient
        wood = (
            1.00 * np.sin(2.0 * np.pi * 435.0 * t) * np.exp(-58.0 * t)
            + 0.78 * np.sin(2.0 * np.pi * 890.0 * t) * np.exp(-85.0 * t)
            + 0.48 * np.sin(2.0 * np.pi * 1540.0 * t) * np.exp(-130.0 * t)
        )
        bark_click = (lowpass(rng.standard_normal(len(t)), 2) - lowpass(rng.standard_normal(len(t)), 9)) * np.exp(-190.0 * t) * 0.75
        amp = np.sin(np.pi * (i + 1.2) / (n_strikes + 1.8)) ** 0.55
        idx = int(t_cursor * RATE)
        seg = (wood + bark_click) * amp
        if idx + len(seg) <= len(out):
            out[idx:idx + len(seg)] += seg
        # Slight natural deceleration in the last 3 taps
        t_cursor += 0.046 + (0.008 if i >= n_strikes - 3 else 0.0)
    # Subtle forest echo tail
    echo_delay = int(0.085 * RATE)
    echo = np.zeros_like(out)
    echo[echo_delay:] = lowpass(out[:-echo_delay], 5) * 0.18
    return out + echo


def make_woodpecker_kix(rng: np.random.Generator) -> np.ndarray:
    """Sharp staccato Buntspecht 'Kix! Kix!' contact call."""
    out = np.zeros(int(RATE * 0.48))
    for start, f_peak in ((0.03, 2950.0), (0.24, 2820.0)):
        dur = 0.052
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f = f_peak * (0.72 + 0.36 * np.sin(np.pi * np.minimum(1.0, u * 2.2)) - 0.18 * u)
        ph = 2.0 * np.pi * np.cumsum(f) / RATE
        sig = np.sin(ph) + 0.42 * np.sin(2.0 * ph) + 0.18 * np.sin(3.0 * ph)
        click = (lowpass(rng.standard_normal(len(t)), 2) - lowpass(rng.standard_normal(len(t)), 7)) * np.exp(-95.0 * t) * 0.35
        env = np.minimum(1.0, u * 28.0) * np.exp(-5.4 * u)
        idx = int(start * RATE)
        out[idx:idx + len(t)] += (sig + click) * env
    return out


def make_woodpecker_klue(rng: np.random.Generator) -> np.ndarray:
    """Ringing woodland woodpecker 'Klü-klü-klü-klü' call."""
    out = np.zeros(int(RATE * 0.72))
    for i in range(4):
        start = 0.03 + i * 0.145
        dur = 0.095
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        base = (2050.0 - i * 85.0)
        f = base * (0.88 + 0.18 * np.sin(np.pi * u * 0.9) - 0.10 * u)
        ph = 2.0 * np.pi * np.cumsum(f) / RATE
        sig = np.sin(ph) + 0.34 * np.sin(2.0 * ph)
        env = np.sin(np.pi * u) ** 0.75 * np.minimum(1.0, u * 18.0)
        idx = int(start * RATE)
        out[idx:idx + len(t)] += sig * env * (1.0 - 0.08 * i)
    return out


def make_jay_raetsch(rng: np.random.Generator, double: bool = False) -> np.ndarray:
    """Harsh rasping Eurasian Jay 'Rääätsch!' sentinel alarm shriek."""
    total = 0.78 if double else 0.46
    out = np.zeros(int(RATE * total))
    calls = ((0.02, 0.34, 1.0), (0.41, 0.31, 0.92)) if double else ((0.03, 0.36, 1.0),)
    for start, dur, gain in calls:
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        # Raspy modulated corvid syrinx around 620 Hz with strong 1.4-2.8 kHz formants + noise grit
        f0 = (640.0 - 115.0 * u) + 52.0 * np.sin(2.0 * np.pi * 68.0 * t)
        ph = 2.0 * np.pi * np.cumsum(f0) / RATE
        harm = np.zeros_like(t)
        for h in range(1, 10):
            hf = h * 600.0
            formant = np.exp(-0.5 * ((hf - 1650.0) / 480.0) ** 2) + 0.75 * np.exp(-0.5 * ((hf - 2650.0) / 550.0) ** 2)
            harm += (0.12 / h + formant) * np.sin(ph * h)
        rasp_mod = 0.58 + 0.42 * np.sin(2.0 * np.pi * 74.0 * t)
        hiss = (lowpass(rng.standard_normal(len(t)), 2) - lowpass(rng.standard_normal(len(t)), 11)) * 0.55
        env = np.minimum(1.0, u * 22.0) * (1.0 - 0.35 * u) * np.sin(np.pi * u) ** 0.42
        seg = lowpass((harm * rasp_mod + hiss) * env, 2) * gain
        idx = int(start * RATE)
        out[idx:idx + len(seg)] += seg[:len(out) - idx]
    return out


def make_robin_song(rng: np.random.Generator, variant: int = 0) -> np.ndarray:
    """Silvery, liquid cascading European Robin warble phrase."""
    out = np.zeros(int(RATE * 0.92))
    if variant == 0:
        notes = [
            (0.03, 0.13, 4150.0, 3850.0, 0.0),
            (0.18, 0.11, 4680.0, 4320.0, 26.0),
            (0.31, 0.16, 3620.0, 3180.0, 34.0),
            (0.49, 0.12, 3980.0, 4420.0, 0.0),
            (0.63, 0.21, 3450.0, 2980.0, 42.0),
        ]
    else:
        # Crisp 'tick-tick' followed by short silvery flourish
        notes = [
            (0.03, 0.026, 4400.0, 2900.0, 0.0),
            (0.12, 0.026, 4350.0, 2850.0, 0.0),
            (0.28, 0.15, 4520.0, 3920.0, 28.0),
            (0.45, 0.19, 3550.0, 4180.0, 36.0),
            (0.66, 0.18, 3280.0, 2860.0, 22.0),
        ]
    for start, dur, f_a, f_b, vib_hz in notes:
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f = f_a + (f_b - f_a) * (u ** 0.85)
        if vib_hz > 0.0:
            f += 135.0 * np.sin(2.0 * np.pi * vib_hz * t)
        ph = 2.0 * np.pi * np.cumsum(f) / RATE
        whistle = np.sin(ph) + 0.16 * np.sin(2.0 * ph)
        env = np.sin(np.pi * u) ** 0.68 * np.minimum(1.0, u * 20.0)
        idx = int(start * RATE)
        out[idx:idx + len(t)] += whistle * env
    return out


def make_duck_call(rng: np.random.Generator, drake: bool = False) -> np.ndarray:
    """Classic Mallard hen nasal decrescendo quacks vs. soft raspy drake 'raeb-raeb'."""
    if drake:
        out = np.zeros(int(RATE * 0.58))
        for start, dur, f0 in ((0.03, 0.21, 235.0), (0.29, 0.22, 222.0)):
            t = np.arange(int(RATE * dur)) / RATE
            u = t / dur
            f = f0 * (1.0 - 0.12 * u) + 8.0 * np.sin(2.0 * np.pi * 46.0 * t)
            ph = 2.0 * np.pi * np.cumsum(f) / RATE
            sig = np.zeros_like(t)
            for h in range(1, 12):
                hf = h * f0
                fm = np.exp(-0.5 * ((hf - 980.0) / 280.0) ** 2) + 0.8 * np.exp(-0.5 * ((hf - 1850.0) / 380.0) ** 2)
                sig += fm * np.sin(ph * h)
            buzz = 0.65 + 0.35 * np.sin(2.0 * np.pi * 55.0 * t)
            env = np.sin(np.pi * u) ** 0.7 * np.minimum(1.0, u * 18.0)
            idx = int(start * RATE)
            out[idx:idx + len(t)] += lowpass(sig * buzz * env, 3)
        return out
    out = np.zeros(int(RATE * 0.76))
    quacks = [(0.02, 0.18, 285.0, 1.0), (0.23, 0.16, 272.0, 0.84), (0.42, 0.15, 258.0, 0.68), (0.59, 0.14, 246.0, 0.52)]
    for start, dur, f0, gain in quacks:
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f = f0 * (1.06 - 0.22 * u)
        ph = 2.0 * np.pi * np.cumsum(f) / RATE
        sig = np.zeros_like(t)
        for h in range(1, 14):
            hf = h * f0
            # Strong nasal duck bill formants around 1.15 kHz and 2.25 kHz
            fm = np.exp(-0.5 * ((hf - 1180.0) / 310.0) ** 2) + 0.72 * np.exp(-0.5 * ((hf - 2280.0) / 420.0) ** 2)
            sig += fm * np.sin(ph * h)
        breath = (lowpass(rng.standard_normal(len(t)), 3) - lowpass(rng.standard_normal(len(t)), 14)) * 0.16
        env = np.minimum(1.0, u * 22.0) * np.exp(-2.1 * u) * np.sin(np.pi * u) ** 0.45
        idx = int(start * RATE)
        seg = lowpass((sig + breath) * env, 2) * gain
        out[idx:idx + len(seg)] += seg[:len(out) - idx]
    return out


def main() -> None:
    rng = np.random.default_rng(20261113)
    save_wav(SFX_DIR / "woodpecker_drum.wav", make_woodpecker_drum(rng), peak=0.48)
    save_wav(SFX_DIR / "jay_alarm.wav", make_jay_raetsch(rng, double=True), peak=0.46)
    save_wav(WILD_DIR / "woodpecker_0.wav", make_woodpecker_kix(rng), peak=0.44)
    save_wav(WILD_DIR / "woodpecker_1.wav", make_woodpecker_klue(rng), peak=0.44)
    save_wav(WILD_DIR / "jay_0.wav", make_jay_raetsch(rng, double=False), peak=0.46)
    save_wav(WILD_DIR / "jay_1.wav", make_jay_raetsch(rng, double=True), peak=0.46)
    save_wav(WILD_DIR / "robin_0.wav", make_robin_song(rng, variant=0), peak=0.42)
    save_wav(WILD_DIR / "robin_1.wav", make_robin_song(rng, variant=1), peak=0.42)
    save_wav(WILD_DIR / "duck_0.wav", make_duck_call(rng, drake=False), peak=0.46)
    save_wav(WILD_DIR / "duck_1.wav", make_duck_call(rng, drake=True), peak=0.44)
    print("Generated 10 bird audio WAV files successfully.")


if __name__ == "__main__":
    main()
