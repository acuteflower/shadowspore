#!/usr/bin/env python3
"""Procedural audio generator for Aurelith, Herz des Sonnenquarzes (Sonnenquarz-Öde Pinnacle Boss).
Writes 18 bespoke 16-bit mono 22050 Hz WAVs into assets/audio/aurelith/:
- awaken_roar.wav       (deep tectonic sandstone grind + rising pentatonic crystal harp chord)
- gauntlet_launch.wav   (heavy stone chain release + rushing desert wind)
- anvil_slam.wav        (colossal sub-bass sandstone impact + shattering sun-quartz chime)
- chain_yank.wav        (taut arcane ley-chain snap + sand drag)
- fault_crack.wav       (3-beat cascading tectonic sun-quartz eruption)
- quicksand_swirl.wav   (low granular sand maelstrom + hollow glass resonance)
- blade_forge.wav       (singing sun-quartz greatsword crystallization + heavy cleave)
- geode_cast.wav        (hollow crystalline geode hurl & crack-open ping)
- mantle_shatter.wav    (Phase 1->2 DER MANTEL BRICHT: shell burst + 8-wing prism chord)
- solar_beam.wav        (focusing solar lens hum + searing prism laser sweep)
- temple_press.wav      (twin monolith walls rising + thunderous horizontal clap)
- mirage_rush.wav       (roaring golden sandstorm rush across the basin)
- solar_meltdown.wav    (Phase 2->3 DIE SONNENSCHMELZE: dry sky-bolt + storm surge)
- tsunami_roar.wav      (arena-wide rolling dune & glass-shard wave)
- core_deflect.wav      (crisp harmonic crystal bell ping when reflecting a Resonanz-Kern)
- zenith_charge.wav     (escalating astral reactor hum for ZENIT-NOVA)
- overheat_stagger.wav  (reactor shatter + exposed rose-cut heart chime)
- harmonic_collapse.wav (weightless antigravity release + deep D-Lydian wind-harp resolution)
"""
import math
import os
import wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "aurelith")
SR = 22050
RNG = np.random.default_rng(20261114)


def save_wav(name: str, samples: np.ndarray, peak_target: float = 0.78) -> None:
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
    print(f"wrote assets/audio/aurelith/{name} ({len(pcm)} samples)")


def smooth_noise(n: int, win: int = 24) -> np.ndarray:
    raw = RNG.standard_normal(n + win)
    kernel = np.ones(win) / float(win)
    return np.convolve(raw, kernel, mode="valid")[:n]


def crystal_bell(t: np.ndarray, f0: float, decay: float) -> np.ndarray:
    return np.exp(-t * decay) * (
        0.58 * np.sin(2.0 * math.pi * f0 * t)
        + 0.28 * np.sin(2.0 * math.pi * (f0 * 2.003) * t)
        + 0.14 * np.sin(2.0 * math.pi * (f0 * 2.996) * t)
    )


def gen_awaken_roar() -> np.ndarray:
    dur = 1.65
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    env = np.minimum(t / 0.18, 1.0) * np.exp(-np.maximum(t - 0.55, 0.0) * 1.9)
    sub_f = 46.0 + 28.0 * (t / dur)
    ph = 2.0 * math.pi * np.cumsum(sub_f) / SR
    stone = env * (0.65 * np.sin(ph) + 0.35 * smooth_noise(n, 38))
    # Rising sun-quartz pentatonic shimmer
    chord = np.zeros_like(t)
    for st, freq in ((0.18, 293.66), (0.36, 440.0), (0.54, 587.33), (0.72, 739.99), (0.90, 1174.66)):
        dt = np.maximum(t - st, 0.0)
        gate = np.where(t >= st, np.minimum(dt / 0.05, 1.0), 0.0)
        chord += gate * 0.22 * crystal_bell(dt, freq, 2.4)
    return stone + chord


def gen_gauntlet_launch() -> np.ndarray:
    dur = 0.58
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    snap = np.exp(-t * 28.0) * (0.6 * np.sin(2.0 * math.pi * 165.0 * t) + 0.4 * crystal_bell(t, 740.0, 14.0))
    sweep_f = 190.0 + 480.0 * (t / dur) ** 1.5
    ph = 2.0 * math.pi * np.cumsum(sweep_f) / SR
    whoosh = np.sin(np.pi * t / dur) * (0.42 * smooth_noise(n, 14) + 0.25 * np.sin(ph))
    return snap + whoosh


def gen_anvil_slam() -> np.ndarray:
    dur = 0.85
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    drop_f = 128.0 * np.exp(-t * 9.5) + 38.0
    ph = 2.0 * math.pi * np.cumsum(drop_f) / SR
    boom = np.exp(-t * 5.2) * (0.78 * np.sin(ph) + 0.45 * smooth_noise(n, 28) * np.exp(-t * 8.0))
    chime = 0.34 * crystal_bell(t, 880.0, 7.5) + 0.22 * crystal_bell(t, 1318.5, 9.5)
    return boom + chime


def gen_chain_yank() -> np.ndarray:
    dur = 0.62
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    twang_f = 520.0 - 210.0 * (t / dur)
    ph = 2.0 * math.pi * np.cumsum(twang_f) / SR
    twang = np.exp(-t * 6.5) * 0.55 * np.sin(ph)
    drag = np.sin(np.pi * np.minimum(t / dur, 1.0)) * 0.48 * smooth_noise(n, 10)
    return twang + drag + 0.24 * crystal_bell(t, 1108.7, 11.0)


def gen_fault_crack() -> np.ndarray:
    dur = 0.92
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    sig = np.zeros_like(t)
    for st, f_base in ((0.0, 587.33), (0.18, 739.99), (0.36, 987.77)):
        dt = np.maximum(t - st, 0.0)
        gate = np.where(t >= st, 1.0, 0.0)
        sig += gate * (
            0.48 * np.exp(-dt * 12.0) * np.sin(2.0 * math.pi * 82.0 * dt)
            + 0.34 * np.exp(-dt * 18.0) * smooth_noise(n, 12)
            + 0.32 * crystal_bell(dt, f_base, 6.8)
        )
    return sig


def gen_quicksand_swirl() -> np.ndarray:
    dur = 1.15
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    env = np.sin(np.pi * t / dur)
    lfo = 0.65 + 0.35 * np.sin(2.0 * math.pi * 5.5 * t)
    grain = env * lfo * 0.55 * smooth_noise(n, 20)
    drone = env * (0.35 * np.sin(2.0 * math.pi * 98.0 * t) + 0.22 * np.sin(2.0 * math.pi * 293.66 * t))
    return grain + drone


def gen_blade_forge() -> np.ndarray:
    dur = 0.78
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    ring = 0.52 * crystal_bell(t, 1046.5, 4.6) + 0.34 * crystal_bell(t, 1567.98, 5.8)
    cleave_t = np.maximum(t - 0.24, 0.0)
    cleave_gate = np.where(t >= 0.24, 1.0, 0.0)
    cleave_f = 420.0 * np.exp(-cleave_t * 6.0) + 75.0
    ph = 2.0 * math.pi * np.cumsum(cleave_f) / SR
    slash = cleave_gate * np.exp(-cleave_t * 7.2) * (0.55 * np.sin(ph) + 0.42 * smooth_noise(n, 8))
    return ring + slash


def gen_geode_cast() -> np.ndarray:
    dur = 0.64
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    thump = np.exp(-t * 14.0) * 0.55 * np.sin(2.0 * math.pi * 135.0 * t)
    dt = np.maximum(t - 0.22, 0.0)
    crack = np.where(t >= 0.22, 1.0, 0.0) * (
        0.45 * crystal_bell(dt, 659.25, 7.5) + 0.35 * crystal_bell(dt, 987.77, 9.0)
    )
    return thump + crack


def gen_mantle_shatter() -> np.ndarray:
    dur = 1.75
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    blast = np.exp(-t * 3.8) * (0.72 * np.sin(2.0 * math.pi * 55.0 * t) + 0.52 * smooth_noise(n, 16) * np.exp(-t * 5.0))
    # Radiant 8-wing prism chord (D4, A4, F#5, A5, C#6, E6)
    chord = np.zeros_like(t)
    for st, freq in ((0.08, 293.66), (0.14, 440.0), (0.20, 739.99), (0.26, 880.0), (0.32, 1108.73), (0.38, 1318.51)):
        dt = np.maximum(t - st, 0.0)
        gate = np.where(t >= st, np.minimum(dt / 0.03, 1.0), 0.0)
        chord += gate * 0.24 * crystal_bell(dt, freq, 1.9)
    return blast + chord


def gen_solar_beam() -> np.ndarray:
    dur = 1.45
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    env = np.minimum(t / 0.12, 1.0) * np.minimum((dur - t) / 0.18, 1.0)
    vib = 1.0 + 0.014 * np.sin(2.0 * math.pi * 19.0 * t)
    ph1 = 2.0 * math.pi * np.cumsum(220.0 * vib) / SR
    ph2 = 2.0 * math.pi * np.cumsum(659.25 * vib) / SR
    searing = env * (0.48 * np.tanh(2.2 * np.sin(ph1)) + 0.34 * np.sin(ph2) + 0.22 * smooth_noise(n, 6))
    return searing


def gen_temple_press() -> np.ndarray:
    dur = 1.15
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    grind = np.where(t < 0.55, 1.0, 0.0) * 0.38 * (smooth_noise(n, 32) + 0.6 * np.sin(2.0 * math.pi * 68.0 * t))
    dt = np.maximum(t - 0.55, 0.0)
    clap = np.where(t >= 0.55, 1.0, 0.0) * (
        0.85 * np.exp(-dt * 7.5) * np.sin(2.0 * math.pi * 52.0 * dt)
        + 0.55 * np.exp(-dt * 14.0) * smooth_noise(n, 10)
        + 0.32 * crystal_bell(dt, 523.25, 8.5)
    )
    return grind + clap


def gen_mirage_rush() -> np.ndarray:
    dur = 0.82
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    env = np.sin(np.pi * t / dur)
    f_sw = 260.0 + 360.0 * np.sin(np.pi * t / dur)
    ph = 2.0 * math.pi * np.cumsum(f_sw) / SR
    return env * (0.58 * smooth_noise(n, 11) + 0.32 * np.sin(ph) + 0.24 * np.sin(ph * 1.5))


def gen_solar_meltdown() -> np.ndarray:
    dur = 1.85
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    bolt = np.exp(-t * 16.0) * smooth_noise(n, 4) * 0.95
    thunder = np.exp(-t * 2.6) * (0.72 * np.sin(2.0 * math.pi * 49.0 * t) + 0.48 * smooth_noise(n, 26))
    storm_harp = (
        0.28 * crystal_bell(np.maximum(t - 0.12, 0.0), 587.33, 1.6)
        + 0.26 * crystal_bell(np.maximum(t - 0.22, 0.0), 932.33, 1.8)
        + 0.24 * crystal_bell(np.maximum(t - 0.32, 0.0), 1174.66, 2.0)
    )
    return bolt + thunder + storm_harp


def gen_tsunami_roar() -> np.ndarray:
    dur = 1.40
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    env = np.minimum(t / 0.25, 1.0) * np.minimum((dur - t) / 0.28, 1.0)
    surf = env * (0.62 * smooth_noise(n, 14) + 0.34 * np.sin(2.0 * math.pi * 64.0 * t))
    glass = env * 0.22 * np.sin(2.0 * math.pi * 1760.0 * t) * (0.5 + 0.5 * np.sin(2.0 * math.pi * 13.0 * t))
    return surf + glass


def gen_core_deflect() -> np.ndarray:
    dur = 0.68
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    hit = np.exp(-t * 34.0) * 0.45 * smooth_noise(n, 5)
    ping = (
        0.55 * crystal_bell(t, 1174.66, 5.5)
        + 0.42 * crystal_bell(np.maximum(t - 0.04, 0.0), 1760.0, 6.2)
        + 0.30 * crystal_bell(np.maximum(t - 0.08, 0.0), 2349.32, 7.5)
    )
    return hit + ping


def gen_zenith_charge() -> np.ndarray:
    dur = 1.95
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    env = np.minimum(t / 0.25, 1.0) * np.minimum((dur - t) / 0.20, 1.0)
    rise = 1.0 + 0.45 * (t / dur) ** 1.3
    sig = np.zeros_like(t)
    for k, amp in ((1.0, 0.42), (1.5, 0.30), (2.0, 0.24), (3.0, 0.16), (4.0, 0.11)):
        ph = 2.0 * math.pi * np.cumsum(146.83 * k * rise) / SR
        sig += amp * np.sin(ph)
    return env * sig


def gen_overheat_stagger() -> np.ndarray:
    dur = 1.35
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    shatter = np.exp(-t * 9.0) * 0.65 * smooth_noise(n, 7)
    drop_f = 680.0 * np.exp(-t * 3.2) + 92.0
    ph = 2.0 * math.pi * np.cumsum(drop_f) / SR
    power_down = np.exp(-t * 2.8) * 0.58 * np.sin(ph)
    heart_expose = 0.38 * crystal_bell(np.maximum(t - 0.12, 0.0), 880.0, 2.8)
    return shatter + power_down + heart_expose


def gen_harmonic_collapse() -> np.ndarray:
    dur = 2.45
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    # Weightless antigravity release + deep warm D-Lydian aeolian resolution chord (D3, A3, F#4, G#4, A4, D5, F#5)
    notes = [
        (0.00, 146.83, 0.44),
        (0.10, 220.00, 0.36),
        (0.22, 369.99, 0.32),
        (0.36, 415.30, 0.24),
        (0.50, 440.00, 0.28),
        (0.66, 587.33, 0.26),
        (0.84, 739.99, 0.22),
    ]
    sig = np.zeros_like(t)
    for st, freq, amp in notes:
        dt = np.maximum(t - st, 0.0)
        gate = np.where(t >= st, np.minimum(dt / 0.09, 1.0), 0.0)
        sig += gate * amp * crystal_bell(dt, freq, 1.25)
    sand_settle = np.exp(-np.maximum(t - 0.4, 0.0) * 2.2) * np.minimum(t / 0.3, 1.0) * 0.16 * smooth_noise(n, 22)
    return sig + sand_settle


def main() -> None:
    save_wav("awaken_roar.wav", gen_awaken_roar())
    save_wav("gauntlet_launch.wav", gen_gauntlet_launch())
    save_wav("anvil_slam.wav", gen_anvil_slam())
    save_wav("chain_yank.wav", gen_chain_yank())
    save_wav("fault_crack.wav", gen_fault_crack())
    save_wav("quicksand_swirl.wav", gen_quicksand_swirl())
    save_wav("blade_forge.wav", gen_blade_forge())
    save_wav("geode_cast.wav", gen_geode_cast())
    save_wav("mantle_shatter.wav", gen_mantle_shatter())
    save_wav("solar_beam.wav", gen_solar_beam())
    save_wav("temple_press.wav", gen_temple_press())
    save_wav("mirage_rush.wav", gen_mirage_rush())
    save_wav("solar_meltdown.wav", gen_solar_meltdown())
    save_wav("tsunami_roar.wav", gen_tsunami_roar())
    save_wav("core_deflect.wav", gen_core_deflect())
    save_wav("zenith_charge.wav", gen_zenith_charge())
    save_wav("overheat_stagger.wav", gen_overheat_stagger())
    save_wav("harmonic_collapse.wav", gen_harmonic_collapse())


if __name__ == "__main__":
    main()
