#!/usr/bin/env python3
"""Synthesized placeholders for the opening of Ellie's room (numpy + stdlib wave): the great crow passing the screen (wind, wing beats), a small crow landing on the sill, the wardrobe door's creak and
its knock into the frame, a breath of air under the white screen. Writes assets/audio/room_intro/*.wav deterministically."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "room_intro"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050


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


def beat(t, at, f0, decay, amp=1.0):
    """One wing beat: a soft low thump and a puff of air."""
    d = np.clip(t - at, 0, None)
    env = np.where(t >= at, np.exp(-d * decay), 0.0) * np.minimum(1.0, d / 0.012)
    return amp * env * np.sin(2 * np.pi * (f0 * np.exp(-d * 3.0)) * d)


# the great crow: wind that swells and falls with it, four heavy wing beats
r = np.random.default_rng(11)
t = tt(2.6)
swell = np.exp(-((t - 1.25) / 0.62) ** 2)
wind = band(r.normal(0, 1, len(t)), 250, 2600) * swell
wind2 = band(r.normal(0, 1, len(t)), 90, 400) * np.exp(-((t - 1.15) / 0.8) ** 2)
beats = sum(beat(t, at, 82, 7.0, 1.4 * np.exp(-((at - 1.2) / 0.9) ** 2)) for at in (0.28, 0.95, 1.62, 2.26))
flutter = band(r.normal(0, 1, len(t)), 700, 3200) * sum(np.where((t > at) & (t < at + 0.14), np.sin(np.pi * (t - at) / 0.14), 0.0) for at in (0.25, 0.92, 1.59, 2.23)) * swell * 0.6
save("crow_pass", wind * 0.8 + wind2 * 0.9 + beats + flutter, 0.8)

# the small crow lands: flaps that slow down, a tick of claws on stone
r = np.random.default_rng(12)
t = tt(1.1)
sig = np.zeros(len(t))
for at, a in ((0.0, 0.9), (0.13, 0.9), (0.28, 0.8), (0.46, 0.7), (0.68, 0.45)):
    burst = band(r.normal(0, 1, len(t)), 500, 3400) * np.where((t > at) & (t < at + 0.1), np.sin(np.pi * (t - at) / 0.1), 0.0)
    sig += burst * a + beat(t, at, 150, 22.0, 0.35 * a)
tick = np.where((t > 0.86) & (t < 0.875), r.normal(0, 1, len(t)), 0.0)
sig += band(tick, 1800, 6000) * 1.5
save("wing_land", sig, 0.45)

# the wardrobe door: a long creak, then the knock of wood on wood and the latch
def creak(length, f0, f1, seed):
    r = np.random.default_rng(seed)
    t = tt(length)
    freq = f0 + (f1 - f0) * (t / t[-1]) + 12 * np.sin(t * 19)
    stick = (r.random(len(t)) > 0.9965).astype(float)
    pulses = np.convolve(stick, np.exp(-np.arange(300) / 40.0), "same")
    tone = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * (0.5 + 0.5 * np.sin(2 * np.pi * 11 * t))
    sig = band(tone + pulses * 4 + r.normal(0, 0.15, len(t)), 160, 1700)
    return sig * np.minimum(1, t / 0.12) * np.minimum(1, (t[-1] - t) / 0.3) * (0.45 + 0.55 * np.sin(np.pi * t / t[-1]))


save("wardrobe_creak", creak(1.6, 190, 300, 5), 0.5)
r = np.random.default_rng(13)
t = tt(0.7)
knock = band(r.normal(0, 1, len(t)), 700, 2400) * np.exp(-t * 55) * 1.0
body = np.sin(2 * np.pi * 70 * np.exp(-t * 3.5) * t) * np.exp(-t * 9) * 1.6
rebound = band(r.normal(0, 1, len(t)), 600, 1800) * np.where(t > 0.11, np.exp(-(t - 0.11) * 70), 0.0) * 0.5
latch = band(r.normal(0, 1, len(t)), 2200, 5200) * np.where(t > 0.21, np.exp(-(t - 0.21) * 160), 0.0) * 0.55
save("wardrobe_thud", knock + body + rebound + latch, 0.7)

# a breath of air under the white screen
r = np.random.default_rng(14)
t = tt(4.5)
air = band(r.normal(0, 1, len(t)), 180, 1100) * (0.55 + 0.45 * np.sin(2 * np.pi * 0.35 * t)) * np.minimum(1, t / 1.5) * np.minimum(1, (t[-1] - t) / 1.2)
air += 0.15 * np.sin(2 * np.pi * 392 * t) * np.sin(np.pi * t / t[-1]) ** 2 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.8 * t))
save("white_air", air, 0.35)

# the shadow smoke lifting out of a hidden room: a low breath that swells and is driven outwards, a dry crackle where the front burns away, a thin high shimmer as the last of it goes
r = np.random.default_rng(15)
t = tt(3.0)
swell = np.exp(-((t - 1.2) / 0.85) ** 2)
breath = band(r.normal(0, 1, len(t)), 70, 520) * swell * 1.2
rush = band(r.normal(0, 1, len(t)), 400, 2400) * np.exp(-((t - 1.5) / 0.7) ** 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 3.1 * t))
sparks = (r.random(len(t)) > 0.9985).astype(float)
crackle = band(np.convolve(sparks, np.exp(-np.arange(200) / 18.0), "same") * r.normal(0, 1, len(t)), 1500, 6500) * np.exp(-((t - 1.3) / 0.9) ** 2) * 3.0
shimmer = band(r.normal(0, 1, len(t)), 3200, 7500) * np.exp(-((t - 2.1) / 0.45) ** 2) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t)) * 0.35
thump = np.sin(2 * np.pi * 52 * np.exp(-t * 2.0) * t) * np.exp(-t * 5.0) * 1.1
save("veil_lift", (breath + rush * 0.7 + crackle + shimmer + thump) * np.minimum(1, t / 0.05) * np.minimum(1, (t[-1] - t) / 0.5), 0.55)
print("wrote", OUT)
