#!/usr/bin/env python3
"""Synthesized placeholders for the boss entrance screen (numpy + stdlib wave), written to assets/audio/boss_intro/*.wav, deterministic:
slam (the black bars snap shut), crackle (a flash of shadow lightning), riser (the dark swell while the boss flies in), boom (the name slams in),
shimmer (the glitch ring after it), exhale (the name and the bars dissolve). Run: py -3 tools/audio_boss_intro.py"""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "boss_intro"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = np.random.default_rng(41)


def tt(s):
    return np.arange(int(RATE * s)) / RATE


def band(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return np.fft.irfft(spec * ((f >= lo) & (f <= hi)), len(x))


def save(name, sig, level=0.7):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * level
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.int16(np.clip(sig, -1, 1) * 32767).tobytes())


# slam: two heavy shutters meeting, a sub thump, a dry crack, a short metallic ring
t = tt(0.9)
thump = np.sin(2 * np.pi * np.cumsum(95 * np.exp(-t * 16) + 42) / RATE) * np.exp(-t * 6.0)
crack = band(rng.normal(0, 1, len(t)), 700, 6000) * np.exp(-t * 38)
swish = band(rng.normal(0, 1, len(t)), 300, 3000) * np.sin(np.pi * np.clip(t / 0.16, 0, 1)) * (t < 0.16)
ring = (np.sin(2 * np.pi * 420 * t) + 0.6 * np.sin(2 * np.pi * 631 * t)) * np.exp(-t * 9) * 0.1
save("slam", thump + crack * 0.8 + swish * 0.5 + ring, 0.85)

# crackle: shadow lightning, a burst of stuttering noise with a thin violet whine
t = tt(0.42)
gate = (np.sin(2 * np.pi * 47 * t + 5 * np.sin(2 * np.pi * 9 * t)) > -0.25).astype(float)
burst = band(rng.normal(0, 1, len(t)), 900, 9000) * gate * np.exp(-t * 9)
whine = np.sin(2 * np.pi * np.cumsum(2400 - 1700 * t / t[-1]) / RATE) * 0.12 * np.exp(-t * 7)
low = np.sin(2 * np.pi * 58 * t) * np.exp(-t * 14) * 0.5
save("crackle", burst + whine + low, 0.6)

# riser: a dark swell rising over the flight: detuned low tones sliding up, wind-like noise growing, a few wing-beat pulses
t = tt(3.4)
x = t / t[-1]
env = np.minimum(1, t / 0.5) * (0.25 + 0.75 * x ** 1.5)
glide = 48 + 38 * x ** 2
tone = np.sin(2 * np.pi * np.cumsum(glide) / RATE) + 0.8 * np.sin(2 * np.pi * np.cumsum(glide * 1.0595 * 1.5) / RATE)
wind = band(rng.normal(0, 1, len(t)), 200, 2600) * (0.15 + 0.85 * x ** 2)
beats = np.sin(2 * np.pi * 2.6 * t) ** 8 * band(rng.normal(0, 1, len(t)), 90, 420) * x
shim = np.sin(2 * np.pi * np.cumsum(900 + 700 * x ** 2) / RATE) * 0.05 * x ** 2
save("riser", (tone * 0.7 + wind * 0.35 + beats * 0.7 + shim) * env, 0.7)

# boom: the name arrives. A deep sub drop, a body hit, a wide crack, a long dark tail with an inharmonic ring
t = tt(3.2)
sub = np.sin(2 * np.pi * np.cumsum(150 * np.exp(-t * 4.5) + 34) / RATE) * np.exp(-t * 1.5)
body = band(rng.normal(0, 1, len(t)), 60, 700) * np.exp(-t * 7)
crack = band(rng.normal(0, 1, len(t)), 1200, 9000) * np.exp(-t * 30)
tail = sum(a * np.sin(2 * np.pi * f * t) for f, a in ((196, 0.5), (293.7, 0.35), (415.3, 0.25), (587.3, 0.14))) * np.exp(-t * 1.3) * (1 - np.exp(-t * 18))
save("boom", sub * 1.0 + body * 0.6 + crack * 0.7 + tail * 0.28, 0.95)

# shimmer: glitchy ring that follows the boom: sample-and-hold tones
t = tt(1.6)
hold = np.floor(t * 16) / 16
freqs = 700 + 900 * np.sin(hold * 91.7) ** 2
sh = np.sin(2 * np.pi * np.cumsum(freqs) / RATE) * np.exp(-t * 2.2) * 0.2 * (1 - np.exp(-t * 40))
grit = band(rng.normal(0, 1, len(t)), 3000, 9000) * (np.sin(2 * np.pi * 13 * t) > 0.4) * np.exp(-t * 4) * 0.2
save("shimmer", sh + grit, 0.5)

# exhale: the name and the bars dissolve, a long breath of dark noise falling in pitch
t = tt(1.5)
x = t / t[-1]
breath = band(rng.normal(0, 1, len(t)), 150, 2200) * np.sin(np.pi * x) ** 1.4
sink = np.sin(2 * np.pi * np.cumsum(120 - 70 * x) / RATE) * np.sin(np.pi * x) * 0.5
save("exhale", breath * 0.6 + sink, 0.55)
print("written to", OUT)
