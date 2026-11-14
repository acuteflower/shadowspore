#!/usr/bin/env python3
"""Synthesises atmospheric audio for VistaPoints -> assets/audio/vistas/:
  - chime.wav       : warm, airy crystal-and-harp discovery chord when a VistaPoint first unveils a valley
  - wind_high.wav   : seamless soft high-altitude breeze loop while seated at a VistaPoint
  - sit_stone.wav   : gentle cloth-and-stone settle sound
"""
import os
import wave
import numpy as np

R = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "vistas")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(4219)


def save_wav(name: str, x: np.ndarray, peak: float = 0.65) -> None:
    m = max(float(np.abs(x).max()), 1e-6)
    y = (x / m) * peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(R)
        w.writeframes((y * 32767.0).astype(np.int16).tobytes())


def warm_tone(f: float, t: np.ndarray, decay: float) -> np.ndarray:
    env = (1.0 - np.exp(-t * 38.0)) * np.exp(-t * decay)
    sig = (
        np.sin(2.0 * np.pi * f * t)
        + 0.34 * np.sin(2.0 * np.pi * f * 2.0 * t) * np.exp(-t * decay * 1.35)
        + 0.14 * np.sin(2.0 * np.pi * f * 3.002 * t) * np.exp(-t * decay * 1.9)
    )
    return sig * env


# 1. chime.wav: Open fifth + ninth arpeggio (D4 - A4 - E5 - F#5 - A5) with airy shimmer
dur = 3.4
chime = np.zeros(int(R * dur), dtype=np.float64)
notes = [
    (0.00, 293.66, 1.35, 0.70),
    (0.11, 440.00, 1.45, 0.62),
    (0.24, 659.25, 1.60, 0.54),
    (0.40, 739.99, 1.75, 0.45),
    (0.58, 880.00, 1.95, 0.42),
]
for delay, freq, dec, amp in notes:
    i0 = int(delay * R)
    n = len(chime) - i0
    tt = np.arange(n) / R
    chime[i0:] += amp * warm_tone(freq, tt, dec)

# Soft breathy tail
tt_all = np.arange(len(chime)) / R
air = rng.standard_normal(len(chime))
kernel = np.hanning(96)
kernel /= kernel.sum()
air_lp = np.convolve(air, kernel, mode="same")
chime += 0.08 * air_lp * (1.0 - np.exp(-tt_all * 4.0)) * np.exp(-tt_all * 1.2)
# Smooth fade-out at end
fade_n = int(R * 0.35)
chime[-fade_n:] *= np.linspace(1.0, 0.0, fade_n)
save_wav("chime", chime, 0.62)

# 2. wind_high.wav: Seamless 6.0s loop of gentle high-plateau wind + faint harmonic resonance
loop_s = 6.0
n_loop = int(R * loop_s)
# Periodic filtered noise via FFT so loop endpoints match with zero click!
freqs = np.fft.rfftfreq(n_loop, d=1.0 / R)
phases = rng.uniform(0.0, 2.0 * np.pi, size=len(freqs))
# Bandpass around 180..620 Hz for soft open valley air
mag = np.exp(-((freqs - 310.0) / 210.0) ** 2) * (freqs / (freqs + 90.0))
mag[0] = 0.0
spec = mag * (np.cos(phases) + 1j * np.sin(phases))
wind = np.fft.irfft(spec, n=n_loop)
wind /= max(float(np.abs(wind).max()), 1e-6)
tl = np.arange(n_loop) / R
# Slow 1-cycle and 2-cycle swell (exact integer cycles over loop_s -> 100% seamless!)
swell = 0.62 + 0.26 * np.sin(2.0 * np.pi * (tl / loop_s)) + 0.12 * np.sin(4.0 * np.pi * (tl / loop_s) + 0.9)
# Very faint singing harmonic pad (D4 + A4 exact integer cycles if rounded to 1/loop_s)
f1 = round(293.66 * loop_s) / loop_s
f2 = round(440.00 * loop_s) / loop_s
pad = 0.14 * np.sin(2.0 * np.pi * f1 * tl) + 0.10 * np.sin(2.0 * np.pi * f2 * tl)
wind_mix = wind * swell * 0.78 + pad * (0.65 + 0.35 * np.sin(2.0 * np.pi * (tl / loop_s) + 1.7))
save_wav("wind_high", wind_mix, 0.38)

# 3. sit_stone.wav: Gentle cloth rustle + soft low tap
ts = np.arange(int(R * 0.24)) / R
rustle = np.convolve(rng.standard_normal(len(ts)), np.hanning(18) / np.hanning(18).sum(), mode="same")
sit = rustle * np.exp(-ts * 19.0) * 0.55 + np.sin(2.0 * np.pi * 138.0 * ts) * np.exp(-ts * 38.0) * 0.45
save_wav("sit_stone", sit, 0.48)

print("wrote vista audio ->", OUT)
