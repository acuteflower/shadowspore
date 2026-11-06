#!/usr/bin/env python3
"""Synthesized placeholders for the death screen (numpy + stdlib wave): the heart that stops, a growl in the dark, the bite,
a low drone for the choice and the airy release when she comes back. Writes assets/audio/death/*.wav deterministically."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "death"
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


def thump(t, at, freq=58.0, decay=9.0):
    x = np.clip(t - at, 0, None)
    return np.sin(2 * np.pi * (freq * x - 18 * (1 - np.exp(-x * 14)) / 14 * 14 * 0.0)) * np.exp(-x * decay) * (t >= at)


# stop: two heartbeats, the second weaker, then the world drains away in a falling tone
t = tt(1.6)
beat = thump(t, 0.0, 62, 10) + 0.6 * thump(t, 0.24, 54, 11)
fall = np.sin(2 * np.pi * np.cumsum(190 * np.exp(-t * 2.4) + 34) / RATE) * np.minimum(1, t / 0.2) * np.exp(-t * 1.5) * 0.35
drain = band(rng.normal(0, 1, len(t)), 90, 700) * np.exp(-t * 2.2) * 0.25
save("stop", beat + fall + drain, 0.8)

# rumble: a low growl that swells; slow tremolo, a band of breath on top, cut off at the peak by the bite
t = tt(1.9)
swell = (t / t[-1]) ** 1.6
saw = ((np.cumsum(np.full(len(t), 46.0)) / RATE) % 1.0 - 0.5) * 2
growl = (saw * 0.6 + np.sin(2 * np.pi * np.cumsum(92 + 8 * np.sin(t * 7)) / RATE) * 0.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t))
breath = band(rng.normal(0, 1, len(t)), 200, 1400) * 0.4 * (0.5 + 0.5 * np.sin(2 * np.pi * 2.2 * t))
save("rumble", (growl * 0.8 + breath) * swell * np.minimum(1, t / 0.25), 0.75)

# bite: crack, crunch, a heavy sub thump and a dying shimmer
t = tt(1.7)
crack = band(rng.normal(0, 1, len(t)), 700, 6000) * np.exp(-t * 55)
crunch = np.zeros(len(t))
for at, gain in ((0.02, 1.0), (0.055, 0.8), (0.09, 0.7), (0.13, 0.5)):
    seg = np.clip(t - at, 0, None)
    crunch += band(rng.normal(0, 1, len(t)), 250, 2400) * np.exp(-seg * 38) * (t >= at) * gain
sub = np.sin(2 * np.pi * np.cumsum(70 * np.exp(-t * 4) + 30) / RATE) * np.exp(-t * 3.2)
tail = band(rng.normal(0, 1, len(t)), 150, 1800) * np.exp(-t * 3.0) * 0.25
shim = np.sin(2 * np.pi * np.cumsum(1320 + 60 * np.sin(t * 6)) / RATE) * 0.06 * np.exp(-t * 2.2)
sig = crack * 0.6 + crunch * 0.7 + sub * 1.1 + tail + shim
echo = np.zeros(len(t))
for d, g in ((0.11, 0.35), (0.23, 0.22), (0.41, 0.12)):
    n = int(d * RATE)
    echo[n:] += band(sig, 120, 1800)[:-n] * g
save("bite", sig + echo, 0.95)

# drone: a low chord breathing, seamless loop (whole cycles in 6 s)
t = tt(6.0)
chord = np.sin(2 * np.pi * 55 * t) + 0.7 * np.sin(2 * np.pi * 82.5 * t) + 0.4 * np.sin(2 * np.pi * 110 * t + 1.0)
breathe = 0.65 + 0.35 * np.sin(2 * np.pi * (2 / 6.0) * t)
hiss = band(rng.normal(0, 1, len(t)), 500, 1600) * 0.08 * (0.5 + 0.5 * np.sin(2 * np.pi * (3 / 6.0) * t))
save("drone", (chord * breathe) * 0.5 + hiss, 0.5)

# return: air rushing up, a soft three-note chime of relief
t = tt(2.0)
env = np.minimum(1, t / 0.5) * np.exp(-np.clip(t - 0.9, 0, None) * 2.0)
sweep = band(rng.normal(0, 1, len(t)), 250, 4200) * env * (0.2 + 0.8 * (t / t[-1]))
chime = np.zeros(len(t))
for at, f in ((0.5, 440.0), (0.78, 660.0), (1.06, 880.0)):
    x = np.clip(t - at, 0, None)
    chime += np.sin(2 * np.pi * f * x) * np.exp(-x * 3.5) * (t >= at) * 0.35
save("return", sweep * 0.7 + chime, 0.6)
print("wrote", sorted(p.name for p in OUT.glob("*.wav")))
