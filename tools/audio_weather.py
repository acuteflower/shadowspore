#!/usr/bin/env python3
"""Synthesized placeholders for the weather (numpy + stdlib wave): six seamless beds (rain light / mid / heavy, wind light / strong, rain on a roof) and
three thunder one-shots (close, mid, far). Writes assets/audio/weather/*.wav (mono, 22050 Hz). `WeatherAudio` crossfades the beds by the rain on the
ground, the wind and where she stands (roof, crown, open sky); thunder plays on WeatherManager.thunder_rolled."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "weather"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
LEN = 12.0
rng = np.random.default_rng(2026)
N = int(RATE * LEN)
t = np.arange(N) / RATE


def band(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    mask = (f >= lo) & (f <= hi)
    return np.fft.irfft(spec * mask, len(x))


def smooth_band(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    g = 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4) / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(spec * g, len(x))


def norm(x, level=0.5):
    return x / (np.max(np.abs(x)) + 1e-9) * level


def swell(cycles, phase, depth=0.45):
    return 1.0 - depth + depth * np.sin(2 * np.pi * (t / LEN * cycles) + phase)  # whole cycles per loop: seamless


def drops(count, f0, f1, amp, decay):
    """Tiny resonant ticks scattered round the loop (wrapping, so the loop stays seamless)."""
    s = np.zeros(N)
    for _ in range(count):
        at = rng.integers(0, N)
        f = rng.uniform(f0, f1)
        n = int(RATE * rng.uniform(0.004, 0.014))
        k = np.arange(n) / RATE
        tick = np.sin(2 * np.pi * f * k) * np.exp(-k * decay) * rng.uniform(0.3, 1.0) * amp
        idx = (at + np.arange(n)) % N
        s[idx] += tick
    return s


def save(name, sig, level=0.55, loop=True, fade=0.03):
    sig = norm(sig, level)
    if not loop:
        ramp = int(fade * RATE)
        sig[:ramp] *= np.linspace(0, 1, ramp)
        sig[-int(0.5 * RATE):] *= np.linspace(1, 0, int(0.5 * RATE)) ** 2
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.int16(np.clip(sig, -1, 1) * 32767).tobytes())


white = lambda: rng.normal(size=N)

# rain: a hiss of many falling drops (band noise) plus the individual ticks
light = smooth_band(white(), 2500, 9000) * 0.35 * swell(2, 0.3, 0.2) + drops(260, 1800, 5200, 0.9, 700)
save("rain_light", light, 0.42)
mid = smooth_band(white(), 900, 8500) * 0.5 * swell(3, 1.1, 0.18) + drops(520, 1200, 4200, 0.7, 600)
save("rain_mid", mid, 0.5)
heavy = smooth_band(white(), 350, 7500) * 0.62 * swell(4, 2.0, 0.16) + smooth_band(white(), 70, 320) * 0.5 * swell(2, 0.5, 0.3) + drops(900, 900, 3600, 0.55, 520)
save("rain_heavy", heavy, 0.56)
roof = drops(1100, 700, 2600, 1.0, 380) + smooth_band(white(), 500, 3800) * 0.18 * swell(3, 0.7, 0.15) + smooth_band(white(), 90, 260) * 0.12
save("rain_roof", roof, 0.5)

# wind: a bed that swells and a howl in the gusts
w_light = smooth_band(white(), 120, 900) * swell(3, 0.0, 0.5) + smooth_band(white(), 900, 2200) * 0.12 * swell(5, 1.3, 0.5)
save("wind_light", w_light, 0.4)
gust = swell(2, 0.4, 0.5) ** 2
howl = np.sin(2 * np.pi * (430 + 90 * np.sin(2 * np.pi * t / LEN * 3)) * t + 4 * np.sin(2 * np.pi * t / LEN * 7)) * gust * 0.10
howl2 = np.sin(2 * np.pi * (610 + 140 * np.sin(2 * np.pi * t / LEN * 2 + 1.0)) * t) * swell(3, 2.0, 0.5) ** 2 * 0.05
w_strong = smooth_band(white(), 90, 1500) * (0.45 + 0.8 * gust) + smooth_band(white(), 1500, 4200) * 0.10 * gust + howl + howl2
save("wind_strong", w_strong, 0.5)


def thunder(name, length, crack, rumble_lo, rumble_hi, delay, amp):
    n = int(RATE * length)
    tt = np.arange(n) / RATE
    noise = rng.normal(size=n)
    out = np.zeros(n)
    if crack > 0:  # the sharp tear of the bolt, a few ms
        c = smooth_band(noise, 700, 9000)
        env = np.exp(-tt * 60) * (tt >= delay)
        out += c * env * crack
        out += smooth_band(rng.normal(size=n), 300, 2500) * np.exp(-np.maximum(tt - delay - 0.05, 0) * 6) * (tt >= delay + 0.05) * crack * 0.5
    r = smooth_band(rng.normal(size=n), rumble_lo, rumble_hi)
    # the roll: several swells with a long decay, like a bolt of many parts
    env = np.zeros(n)
    for k in range(rng.integers(4, 8)):
        at = delay + rng.uniform(0.0, length * 0.55)
        env += np.exp(-np.maximum(tt - at, 0) * rng.uniform(0.7, 1.6)) * (tt >= at) * rng.uniform(0.3, 1.0)
    env *= np.minimum((tt - delay).clip(0) * 9, 1.0)
    out += r * env * amp
    out += np.sin(2 * np.pi * 42 * tt) * env * amp * 0.25  # a low body
    save(name, out, 0.85, loop=False, fade=0.002)


thunder("thunder_close", 7.0, 1.0, 40, 900, 0.0, 1.3)
thunder("thunder_mid", 8.5, 0.35, 40, 600, 0.35, 1.2)
thunder("thunder_far", 9.5, 0.0, 35, 280, 0.9, 1.1)
print("weather audio written to", OUT)
