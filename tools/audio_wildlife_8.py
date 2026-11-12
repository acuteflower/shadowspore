#!/usr/bin/env python3
"""Deterministic procedural acoustic calls for the 8 new wildlife species (numpy + stdlib).
Writes:
  assets/audio/sfx/{boar_grunt,boar_snort,lynx_call,squirrel_chatter,goat_bleat,toad_croak,owl_hoot}.wav
  assets/audio/wildlife/{owl_0,owl_1,otter_0,otter_1}.wav
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


def save_wav(path: Path, signal: np.ndarray, peak: float = 0.52) -> None:
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


def formant_voice(f: np.ndarray, formants: list[float], rng: np.random.Generator, breath: float = 0.08, harmonics: int = 18) -> np.ndarray:
    phase = np.cumsum(f) * (2.0 * np.pi / RATE)
    sig = np.zeros_like(f, dtype=np.float64)
    base = float(np.mean(f))
    for h in range(1, harmonics + 1):
        weight = 0.06 / h + sum(
            np.exp(-0.5 * ((h * base - fm) / (fm * 0.24)) ** 2) for fm in formants
        ) / (1.0 + h * 0.16)
        sig += weight * np.sin(phase * h)
    if breath > 0.0:
        n = rng.standard_normal(len(f))
        sig += breath * (lowpass(n, 4) - lowpass(n, 28))
    return sig


def make_boar_grunt(rng: np.random.Generator) -> np.ndarray:
    """Two low guttural nasal boar grunts."""
    out = np.zeros(int(RATE * 0.68))
    for start, dur, f0 in ((0.02, 0.24, 86.0), (0.33, 0.29, 78.0)):
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f = f0 * (1.0 + 0.12 * np.sin(np.pi * u) - 0.14 * u) + 5.0 * np.sin(2.0 * np.pi * 29.0 * t)
        fry = 0.68 + 0.32 * np.sin(2.0 * np.pi * 34.0 * t)
        g = formant_voice(f, [240.0, 620.0, 1180.0], rng, breath=0.18) * fry
        env = np.sin(np.pi * u) ** 0.75 * np.minimum(1.0, u * 16.0)
        idx = int(start * RATE)
        seg = lowpass(g * env, 4)
        out[idx:idx + len(seg)] += seg[:len(out) - idx]
    return out


def make_boar_snort(rng: np.random.Generator) -> np.ndarray:
    """Sharp defensive nasal breath-blast + low chest rumble."""
    dur = 0.42
    t = np.arange(int(RATE * dur)) / RATE
    u = t / dur
    n = rng.standard_normal(len(t))
    blast = (lowpass(n, 3) - lowpass(n, 22)) * (0.7 + 0.3 * np.sin(2.0 * np.pi * 42.0 * t))
    rumble = formant_voice(94.0 - 22.0 * u, [280.0, 740.0], rng, breath=0.05) * 0.55
    env = np.minimum(1.0, u * 24.0) * np.exp(-3.8 * u) * np.sin(np.pi * u) ** 0.35
    return (blast + rumble) * env


def make_lynx_call(rng: np.random.Generator) -> np.ndarray:
    """Rare, eerie muffled feline forest call ('rra-oow')."""
    dur = 0.66
    t = np.arange(int(RATE * dur)) / RATE
    u = t / dur
    f = 310.0 + 145.0 * np.sin(np.pi * np.clip(u * 1.15, 0.0, 1.0)) ** 1.4 - 95.0 * u
    f += 6.0 * np.sin(2.0 * np.pi * 22.0 * t)
    v = formant_voice(f, [580.0, 1250.0, 2300.0], rng, breath=0.10)
    rasp = 0.82 + 0.18 * np.sin(2.0 * np.pi * 52.0 * t)
    env = np.sin(np.pi * u) ** 0.85 * np.minimum(1.0, u * 14.0)
    return lowpass(v * rasp * env, 3)


def make_squirrel_chatter(rng: np.random.Generator) -> np.ndarray:
    """Rapid staccato tree-trunk scold: three sharp 'chuk' clicks + short trill."""
    out = np.zeros(int(RATE * 0.62))
    for i, start in enumerate((0.02, 0.13, 0.24)):
        dur = 0.048
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f = (1850.0 - 750.0 * u) * (1.0 + 0.04 * i)
        bark = (np.sin(2.0 * np.pi * np.cumsum(f) / RATE) + 0.45 * np.sin(4.0 * np.pi * np.cumsum(f) / RATE))
        click = (lowpass(rng.standard_normal(len(t)), 2) - lowpass(rng.standard_normal(len(t)), 8)) * 0.45
        env = np.minimum(1.0, u * 30.0) * np.exp(-6.5 * u)
        idx = int(start * RATE)
        out[idx:idx + len(t)] += (bark + click) * env
    # Short woody buzz trill at the end
    t_tr = np.arange(int(RATE * 0.20)) / RATE
    u_tr = t_tr / 0.20
    f_tr = 1320.0 - 260.0 * u_tr + 90.0 * np.sin(2.0 * np.pi * 38.0 * t_tr)
    pulse = 0.55 + 0.45 * np.sin(2.0 * np.pi * 38.0 * t_tr)
    trill = np.sin(2.0 * np.pi * np.cumsum(f_tr) / RATE) * pulse * np.sin(np.pi * u_tr) ** 0.7
    idx = int(0.37 * RATE)
    out[idx:idx + len(t_tr)] += trill * 0.75
    return out


def make_goat_bleat(rng: np.random.Generator) -> np.ndarray:
    """Low, gnarled, vibrato caprid bleat of the Hexenwald billy goat."""
    dur = 0.64
    t = np.arange(int(RATE * dur)) / RATE
    u = t / dur
    trem = np.sin(2.0 * np.pi * 13.5 * t)
    f = (168.0 - 24.0 * u) * (1.0 + 0.055 * trem)
    v = formant_voice(f, [480.0, 1120.0, 2150.0], rng, breath=0.11, harmonics=22)
    amp_mod = 0.68 + 0.32 * np.maximum(0.0, trem)
    env = np.minimum(1.0, u * 18.0) * np.sin(np.pi * u) ** 0.65
    return lowpass(v * amp_mod * env, 2)


def make_toad_croak(rng: np.random.Generator) -> np.ndarray:
    """Deep, hollow fairy-ring Unkenruf: two low resonant vocal-sac booms."""
    out = np.zeros(int(RATE * 0.82))
    for start, dur, f0 in ((0.03, 0.28, 138.0), (0.42, 0.33, 126.0)):
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f = f0 * (1.0 + 0.05 * np.sin(np.pi * u) - 0.06 * u)
        phase = 2.0 * np.pi * np.cumsum(f) / RATE
        # Hollow ocarina/sac resonance with subtle throat pulse
        sac = np.sin(phase) + 0.32 * np.sin(2.0 * phase) + 0.08 * np.sin(3.0 * phase)
        burr = 0.86 + 0.14 * np.sin(2.0 * np.pi * 31.0 * t)
        env = np.sin(np.pi * u) ** 1.15
        idx = int(start * RATE)
        seg = lowpass(sac * burr * env, 5)
        out[idx:idx + len(seg)] += seg[:len(out) - idx]
    return out


def make_eagle_owl_hoot(variant: int, rng: np.random.Generator) -> np.ndarray:
    """Deep resonant Eurasian Eagle-Owl ('U-huuu') two-part nocturnal hoot."""
    out = np.zeros(int(RATE * (1.18 + 0.08 * variant)))
    # First note: higher 'Uu', pause, deeper drawn-out 'huuuu'
    notes = [
        (0.04, 0.28, 298.0 - 12.0 * variant, 282.0 - 12.0 * variant),
        (0.44, 0.62 + 0.06 * variant, 254.0 - 10.0 * variant, 226.0 - 10.0 * variant),
    ]
    for start, dur, f_start, f_end in notes:
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f = f_start + (f_end - f_start) * (u ** 0.75) + 1.8 * np.sin(2.0 * np.pi * 5.5 * t)
        phase = 2.0 * np.pi * np.cumsum(f) / RATE
        pure = np.sin(phase) + 0.16 * np.sin(2.0 * phase) + 0.03 * np.sin(3.0 * phase)
        air = (lowpass(rng.standard_normal(len(t)), 8) - lowpass(rng.standard_normal(len(t)), 36)) * 0.06
        env = np.minimum(1.0, u * 10.0) * (np.sin(np.pi * u) ** 0.85)
        idx = int(start * RATE)
        seg = (pure + air) * env
        out[idx:idx + len(seg)] += seg[:len(out) - idx]
    return out


def make_otter_chirp(variant: int, rng: np.random.Generator) -> np.ndarray:
    """Soft, playful Eurasian otter contact whistle-chirp."""
    out = np.zeros(int(RATE * 0.46))
    notes = [(0.03, 0.13, 2350.0 + 120.0 * variant), (0.21, 0.16, 2620.0 + 90.0 * variant)]
    for start, dur, f0 in notes:
        t = np.arange(int(RATE * dur)) / RATE
        u = t / dur
        f = f0 * (1.0 + 0.16 * np.sin(np.pi * u) - 0.10 * u) + 45.0 * np.sin(2.0 * np.pi * 28.0 * t)
        phase = 2.0 * np.pi * np.cumsum(f) / RATE
        whistle = np.sin(phase) + 0.22 * np.sin(2.0 * phase)
        breath = (lowpass(rng.standard_normal(len(t)), 3) - lowpass(rng.standard_normal(len(t)), 14)) * 0.09
        env = np.minimum(1.0, u * 20.0) * np.exp(-3.6 * u) * np.sin(np.pi * u) ** 0.5
        idx = int(start * RATE)
        seg = (whistle + breath) * env
        out[idx:idx + len(seg)] += seg[:len(out) - idx]
    return out


def main() -> None:
    rng = np.random.default_rng(20261112)
    save_wav(SFX_DIR / 'boar_grunt.wav', make_boar_grunt(rng), peak=0.48)
    save_wav(SFX_DIR / 'boar_snort.wav', make_boar_snort(rng), peak=0.46)
    save_wav(SFX_DIR / 'lynx_call.wav', make_lynx_call(rng), peak=0.42)
    save_wav(SFX_DIR / 'squirrel_chatter.wav', make_squirrel_chatter(rng), peak=0.40)
    save_wav(SFX_DIR / 'goat_bleat.wav', make_goat_bleat(rng), peak=0.46)
    save_wav(SFX_DIR / 'toad_croak.wav', make_toad_croak(rng), peak=0.48)
    owl0 = make_eagle_owl_hoot(0, rng)
    owl1 = make_eagle_owl_hoot(1, rng)
    save_wav(SFX_DIR / 'owl_hoot.wav', owl0, peak=0.44)
    save_wav(WILD_DIR / 'owl_0.wav', owl0, peak=0.42)
    save_wav(WILD_DIR / 'owl_1.wav', owl1, peak=0.42)
    save_wav(WILD_DIR / 'otter_0.wav', make_otter_chirp(0, rng), peak=0.38)
    save_wav(WILD_DIR / 'otter_1.wav', make_otter_chirp(1, rng), peak=0.38)
    print('Wrote 11 wildlife audio WAV files.')


if __name__ == '__main__':
    main()
