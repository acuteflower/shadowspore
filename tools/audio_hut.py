#!/usr/bin/env python3
"""Synthesized placeholders for the hut (numpy + stdlib wave): wood creaks, a pained groan, cloth rustle, the door, and the room's ambience (wind through the
cracks, a fire crackling, a few distant birds; a seamless loop). Writes assets/audio/hut/*.wav deterministically."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "hut"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = np.random.default_rng(57)


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


def creak(length, f0, f1, seed):
    r = np.random.default_rng(seed)
    t = tt(length)
    freq = f0 + (f1 - f0) * (t / t[-1]) + 14 * np.sin(t * 23)
    stick = (r.random(len(t)) > 0.9965).astype(float)  # the wood sticks and slips: tiny pulses
    pulses = np.convolve(stick, np.exp(-np.arange(300) / 40.0), "same")
    tone = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * (0.5 + 0.5 * np.sin(2 * np.pi * 13 * t))
    sig = band(tone + pulses * 4 + r.normal(0, 0.15, len(t)), 180, 1800)
    return sig * np.minimum(1, t / 0.08) * np.minimum(1, (t[-1] - t) / 0.2)


save("creak_a", creak(0.9, 310, 240, 1), 0.55)
save("creak_b", creak(1.2, 180, 260, 2), 0.55)

# groan: a pained, breathy "mmh" going down
t = tt(1.1)
f = 150 - 40 * (t / t[-1]) + 4 * np.sin(t * 40)
saw = ((np.cumsum(f) / RATE) % 1.0 - 0.5) * 2
voice = band(saw, 220, 1100) * 0.8 + band(rng.normal(0, 1, len(t)), 700, 2400) * 0.25
save("groan", voice * np.sin(np.pi * np.clip(t / t[-1], 0, 1)) ** 0.7, 0.6)

# rustle: cloth and straw being moved
t = tt(0.9)
env = np.abs(np.sin(2 * np.pi * 7 * t) * np.sin(2 * np.pi * 2.3 * t + 1)) * np.sin(np.pi * t / t[-1])
save("rustle", band(rng.normal(0, 1, len(t)), 1500, 6000) * env, 0.5)

# door: open (a long creak and a latch), close (a thud and a short creak)
c = creak(1.0, 260, 190, 5)
latch = np.zeros(len(c))
latch[:300] = band(rng.normal(0, 1, 300), 800, 5000) * np.exp(-np.arange(300) / 60.0)
save("door_open", c * 0.8 + latch, 0.65)
t = tt(0.8)
thud = np.sin(2 * np.pi * 70 * t) * np.exp(-t * 11) + band(rng.normal(0, 1, len(t)), 150, 1500) * np.exp(-t * 30) * 0.8
save("door_close", thud + np.pad(creak(0.5, 200, 240, 6) * 0.35, (0, len(t) - int(0.5 * RATE)))[:len(t)] * 0.5, 0.7)

# drip: a water drop on wood: a short high plop with a little room
t = tt(0.5)
plop = np.sin(2 * np.pi * np.cumsum(1800 - 1300 * np.minimum(t * 12, 1)) / RATE) * np.exp(-t * 30)
tail = band(rng.normal(0, 1, len(t)), 600, 3000) * np.exp(-t * 14) * 0.15
save("drip", plop + tail, 0.5)

# ambience: wind through the cracks, a fire, a few birds; 10 s, the ends cross-faded into a loop
length = 10.0
t = tt(length)
wind = band(rng.normal(0, 1, len(t)), 80, 520) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.17 * t + 1)) ** 1.5 * 0.55
wind += band(rng.normal(0, 1, len(t)), 900, 1800) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.3 * t)) ** 3 * 0.1
fire = np.zeros(len(t))
for _ in range(60):
    at = rng.integers(0, len(t) - 400)
    n = rng.integers(40, 200)
    fire[at:at + n] += band(rng.normal(0, 1, n), 1500, 7000) * np.exp(-np.arange(n) / (n / 4)) * rng.uniform(0.2, 0.7)
fire += band(rng.normal(0, 1, len(t)), 100, 400) * 0.12
birds = np.zeros(len(t))
for at in (1.8, 2.05, 5.6, 5.8, 6.0, 8.4):
    s = int(at * RATE)
    n = int(0.16 * RATE)
    k = np.arange(n) / RATE
    f = 3000 + 900 * np.sin(k * 60) + (rng.random() * 600)
    birds[s:s + n] += np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.sin(np.pi * k / k[-1]) * 0.07
amb = wind + fire * 0.35 + birds
xf = int(0.8 * RATE)
head = amb[:xf].copy()
fade = np.linspace(0, 1, xf)
amb[-xf:] = amb[-xf:] * (1 - fade) + head * fade
save("ambient", amb[: len(amb) - 0], 0.5)
# the fire pit in the yard: a soft roar, the dense crackle of dry wood, now and then a sharp pop; 7 s, a seamless loop (assets/audio/hut/fire.wav)
length = 7.0
t = tt(length)
roar = band(rng.normal(0, 1, len(t)), 60, 380) * (0.65 + 0.35 * np.sin(2 * np.pi * 0.43 * t + 0.4)) * 0.5
roar += band(rng.normal(0, 1, len(t)), 700, 2200) * (0.5 + 0.5 * np.sin(2 * np.pi * 1.7 * t)) ** 2 * 0.07
crackle = np.zeros(len(t))
for _ in range(150):
    at = rng.integers(0, len(t) - 600)
    n = rng.integers(30, 160)
    crackle[at:at + n] += band(rng.normal(0, 1, n), 1800, 8000) * np.exp(-np.arange(n) / (n / 5)) * rng.uniform(0.15, 0.6)
for at in (0.9, 2.6, 4.1, 5.7):  # a pop
    s0 = int(at * RATE)
    n = 420
    crackle[s0:s0 + n] += band(rng.normal(0, 1, n), 500, 4500) * np.exp(-np.arange(n) / 70.0) * 1.3
fire_loop = roar + crackle * 0.5
xf = int(0.6 * RATE)
fire_loop[-xf:] = fire_loop[-xf:] * (1 - np.linspace(0, 1, xf)) + fire_loop[:xf] * np.linspace(0, 1, xf)
save("fire", fire_loop, 0.55)
print("wrote", sorted(p.name for p in OUT.glob("*.wav")))
