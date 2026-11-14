#!/usr/bin/env python3
"""Synthesises atmospheric audio for standard-meadow POIs & Wonders -> assets/audio/meadow_wonders/:
  - order_stone.wav      : resonant stone touch + faint solemn brass-fifth echo (Red Order monuments)
  - mill_unjam.wav       : snapping driftwood wedge + heavy oak wheel groaning to life + splash
  - mill_creak_loop.wav  : seamless 4.0s gentle wooden waterwheel creak & water paddle loop
  - bell_underwater.wav  : deep, haunting submerged bronze bell toll at midnight on the Glockenteich
  - guardian_chord.wav   : ancient 7-voice stone-and-choir harmonic blessing chord
  - amphitheater_hum.wav : shimmering celestial wisp-waltz harmonic swell
  - starfall_streak.wav  : crystalline high-sky shooting star whistle & shimmer
  - starfall_impact.wav  : warm distant earth thud + singing meteorite chime
  - stag_chime.wav       : gentle breathy silver-flute & dewdrop chime for the White Crowned Stag
  - stag_paw.wav         : soft mossy hoof pawing sound
"""
import os
import wave
import numpy as np

R = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "meadow_wonders")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7731)


def save_wav(name: str, x: np.ndarray, peak: float = 0.65) -> None:
    m = max(float(np.abs(x).max()), 1e-6)
    y = np.clip((x / m) * peak, -1.0, 1.0)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(R)
        w.writeframes((y * 32767.0).astype(np.int16).tobytes())


def smooth_noise(n: int, width: int) -> np.ndarray:
    raw = rng.standard_normal(n)
    k = np.hanning(max(width, 4))
    k /= k.sum()
    return np.convolve(raw, k, mode="same")


# 1. order_stone.wav: solemn stone knock + warm low fifth (A2 + E3 + C#4)
t1 = np.arange(int(R * 1.9)) / R
knock = smooth_noise(len(t1), 24) * np.exp(-t1 * 42.0) * 0.55 + np.sin(2.0 * np.pi * 110.0 * t1) * np.exp(-t1 * 22.0) * 0.45
horn = (
    0.55 * np.sin(2.0 * np.pi * 110.0 * t1)
    + 0.42 * np.sin(2.0 * np.pi * 164.81 * t1)
    + 0.24 * np.sin(2.0 * np.pi * 220.0 * t1)
    + 0.15 * np.sin(2.0 * np.pi * 277.18 * t1)
) * (1.0 - np.exp(-t1 * 8.0)) * np.exp(-t1 * 1.85)
sig1 = knock + horn * 0.72
sig1[-int(R * 0.25):] *= np.linspace(1.0, 0.0, int(R * 0.25))
save_wav("order_stone", sig1, 0.58)

# 2. mill_unjam.wav: wood crack + chain clink + water surge
t2 = np.arange(int(R * 1.6)) / R
crack = smooth_noise(len(t2), 10) * np.exp(-t2 * 35.0) * 0.8
crack2_i = int(0.14 * R)
crack[crack2_i:] += smooth_noise(len(t2) - crack2_i, 14) * np.exp(-np.arange(len(t2) - crack2_i) / R * 28.0) * 0.65
groan = np.sin(2.0 * np.pi * (68.0 + 14.0 * np.sin(t2 * 5.0)) * t2) * (1.0 - np.exp(-t2 * 10.0)) * np.exp(-t2 * 2.4) * 0.45
splash = smooth_noise(len(t2), 36) * (1.0 - np.exp(-np.maximum(t2 - 0.2, 0.0) * 9.0)) * np.exp(-np.maximum(t2 - 0.2, 0.0) * 2.2) * 0.55
sig2 = crack + groan + splash
sig2[-int(R * 0.2):] *= np.linspace(1.0, 0.0, int(R * 0.2))
save_wav("mill_unjam", sig2, 0.64)

# 3. mill_creak_loop.wav: seamless 4.0s waterwheel paddle & timber creak loop
loop_s = 4.0
nl = int(R * loop_s)
freqs = np.fft.rfftfreq(nl, d=1.0 / R)
ph = rng.uniform(0.0, 2.0 * np.pi, size=len(freqs))
mag = np.exp(-((freqs - 420.0) / 280.0) ** 2) * (freqs / (freqs + 120.0))
mag[0] = 0.0
water_bed = np.fft.irfft(mag * (np.cos(ph) + 1j * np.sin(ph)), n=nl)
water_bed /= max(float(np.abs(water_bed).max()), 1e-6)
tl = np.arange(nl) / R
# 4 gentle paddle dips per 4s loop (exact integer period)
paddle_env = 0.55 + 0.45 * (0.5 + 0.5 * np.sin(2.0 * np.pi * 1.0 * tl)) ** 2
# Subtle wood creak once per revolution (4s)
creak_win = np.exp(-((tl - 1.8) / 0.22) ** 2)
f_creak = round(142.0 * loop_s) / loop_s
creak_tone = (np.sin(2.0 * np.pi * f_creak * tl) + 0.4 * np.sin(2.0 * np.pi * f_creak * 2.0 * tl)) * creak_win * 0.24
save_wav("mill_creak_loop", water_bed * paddle_env * 0.65 + creak_tone, 0.36)

# 4. bell_underwater.wav: deep muffled underwater bronze bell toll (D3 + A3 + F4 + pitch-glide water shimmer)
t4 = np.arange(int(R * 4.4)) / R
# Underwater pitch bend (slight downward settling + slow beat)
partials = [
    (146.83, 0.75, 1.00),
    (147.45, 0.70, 0.45),  # warm beat
    (220.00, 1.05, 0.52),
    (293.66, 1.25, 0.42),
    (349.23, 1.65, 0.28),
    (440.00, 2.10, 0.20),
    (587.33, 2.80, 0.11),
]
bell = np.zeros_like(t4)
for f, dec, amp in partials:
    wobble = 1.0 + 0.0035 * np.sin(2.0 * np.pi * 2.1 * t4)
    bell += amp * np.sin(2.0 * np.pi * f * wobble * t4) * (1.0 - np.exp(-t4 * 26.0)) * np.exp(-t4 * dec)
# Muffled low-frequency water thump + bubble ripple
thump = np.sin(2.0 * np.pi * 73.4 * t4) * (1.0 - np.exp(-t4 * 45.0)) * np.exp(-t4 * 3.8) * 0.55
rip = smooth_noise(len(t4), 90) * (1.0 - np.exp(-t4 * 6.0)) * np.exp(-t4 * 1.1) * 0.14
sig4 = bell * 0.78 + thump + rip
sig4[-int(R * 0.5):] *= np.linspace(1.0, 0.0, int(R * 0.5))
save_wav("bell_underwater", sig4, 0.68)

# 5. guardian_chord.wav: ancient 7-stone rising harmonic blessing (D3 -> A3 -> D4 -> F#4 -> A4 -> C#5 -> E5)
t5 = np.arange(int(R * 3.8)) / R
sig5 = np.zeros_like(t5)
g_notes = [146.83, 220.00, 293.66, 369.99, 440.00, 554.37, 659.25]
for idx, f in enumerate(g_notes):
    i0 = int(idx * 0.14 * R)
    tt = np.arange(len(t5) - i0) / R
    env = (1.0 - np.exp(-tt * 14.0)) * np.exp(-tt * 0.95)
    voice = (np.sin(2.0 * np.pi * f * tt) + 0.3 * np.sin(2.0 * np.pi * f * 2.0 * tt) * np.exp(-tt * 1.6)) * env
    sig5[i0:] += voice * (0.45 - idx * 0.035)
sig5[-int(R * 0.45):] *= np.linspace(1.0, 0.0, int(R * 0.45))
save_wav("guardian_chord", sig5, 0.64)

# 6. amphitheater_hum.wav: luminous wisp-dance celesta & airy pad (4.2s)
t6 = np.arange(int(R * 4.2)) / R
sig6 = np.zeros_like(t6)
arp = [587.33, 659.25, 739.99, 880.00, 1174.66, 880.00, 739.99, 1318.51]
for idx, f in enumerate(arp):
    i0 = int(idx * 0.32 * R)
    if i0 >= len(t6):
        break
    tt = np.arange(len(t6) - i0) / R
    sig6[i0:] += 0.28 * np.sin(2.0 * np.pi * f * tt) * (1.0 - np.exp(-tt * 40.0)) * np.exp(-tt * 1.9)
pad6 = (0.32 * np.sin(2.0 * np.pi * 293.66 * t6) + 0.26 * np.sin(2.0 * np.pi * 440.0 * t6)) * np.sin(np.pi * t6 / 4.2) ** 1.4
sig6 += pad6
sig6[-int(R * 0.4):] *= np.linspace(1.0, 0.0, int(R * 0.4))
save_wav("amphitheater_hum", sig6, 0.58)

# 7. starfall_streak.wav: crystalline descending sky shimmer
t7 = np.arange(int(R * 1.8)) / R
f_sweep = 1760.0 * np.exp(-t7 * 0.58)
streak = (
    0.45 * np.sin(2.0 * np.pi * np.cumsum(f_sweep) / R)
    + 0.28 * np.sin(2.0 * np.pi * np.cumsum(f_sweep * 1.498) / R)
    + 0.22 * smooth_noise(len(t7), 16)
) * np.sin(np.pi * np.minimum(t7 / 1.8, 1.0)) ** 1.2
save_wav("starfall_streak", streak, 0.52)

# 8. starfall_impact.wav: warm soft earth thud + singing star-ore bell
t8 = np.arange(int(R * 2.2)) / R
earth = np.sin(2.0 * np.pi * (92.0 * np.exp(-t8 * 2.2) + 42.0) * t8) * np.exp(-t8 * 5.5) * 0.75
ore_ring = (
    0.38 * np.sin(2.0 * np.pi * 523.25 * t8)
    + 0.28 * np.sin(2.0 * np.pi * 783.99 * t8)
    + 0.18 * np.sin(2.0 * np.pi * 1174.66 * t8)
) * (1.0 - np.exp(-t8 * 25.0)) * np.exp(-t8 * 1.65)
sig8 = earth + ore_ring
sig8[-int(R * 0.25):] *= np.linspace(1.0, 0.0, int(R * 0.25))
save_wav("starfall_impact", sig8, 0.62)

# 9. stag_chime.wav: ethereal breathy flute + silver dewdrop harmonic
t9 = np.arange(int(R * 2.1)) / R
flute = (
    0.50 * np.sin(2.0 * np.pi * 587.33 * t9)
    + 0.34 * np.sin(2.0 * np.pi * 880.00 * t9)
    + 0.22 * np.sin(2.0 * np.pi * 1318.51 * np.maximum(t9 - 0.18, 0.0)) * (t9 > 0.18)
    + 0.08 * smooth_noise(len(t9), 42)
) * (1.0 - np.exp(-t9 * 11.0)) * np.exp(-t9 * 1.6)
flute[-int(R * 0.25):] *= np.linspace(1.0, 0.0, int(R * 0.25))
save_wav("stag_chime", flute, 0.50)

# 10. stag_paw.wav: soft mossy hoof brush & dull earth tap
t10 = np.arange(int(R * 0.28)) / R
paw = smooth_noise(len(t10), 20) * np.exp(-t10 * 18.0) * 0.6 + np.sin(2.0 * np.pi * 124.0 * t10) * np.exp(-t10 * 34.0) * 0.4
save_wav("stag_paw", paw, 0.48)

print("Generated 10 WAV files in assets/audio/meadow_wonders/")
