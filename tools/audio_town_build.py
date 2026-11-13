#!/usr/bin/env python3
"""Synthesized placeholders for building in the town (docs/stadtbau_konzept.md; numpy + stdlib wave): the foundation stone, hammer blows while lending a hand,
the milestones, the consecration (impact, bell, the pressure wave, plants torn out, the light flooding out), the town's motif when you walk in, the level bells,
the cards of the build plan and the banner unrolling. Writes assets/audio/town/*.wav deterministically."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "town"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = np.random.default_rng(417)


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


def env(t, attack, decay):
    return np.minimum(1.0, t / attack) * np.exp(-t / decay)


def noise(n, lo, hi):
    return band(rng.normal(0, 1, n), lo, hi)


def bell(t, f, decay, partials=((1, 1.0), (2.01, 0.5), (2.76, 0.35), (4.07, 0.2), (5.43, 0.1))):
    out = np.zeros_like(t)
    for ratio, amp in partials:
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / (decay / ratio ** 0.6))
    return out * np.minimum(1, t / 0.004)


def thud(length, f0, f1, decay):
    t = tt(length)
    freq = f1 + (f0 - f1) * np.exp(-t * 18)
    body = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * env(t, 0.003, decay)
    grit = noise(len(t), 150, 2500) * env(t, 0.002, decay * 0.35) * 0.6
    return body + grit


# the foundation stone lands: a heavy stone knock with a rune ping
t = tt(0.9)
save("stone_set", thud(0.9, 140, 48, 0.16) * 1.4 + bell(t, 880, 0.35) * 0.18, 0.8)

# material lands on the site: a short wooden clatter
t = tt(0.35)
clack = np.zeros(len(t))
for at in (0.0, 0.06, 0.11, 0.19):
    i = int(at * RATE)
    k = tt(0.12)
    clack[i:i + len(k)] += np.sin(2 * np.pi * rng.uniform(380, 620) * k) * env(k, 0.001, 0.025)
save("material_land", band(clack + rng.normal(0, 0.05, len(t)), 150, 4000), 0.5)

# the snap of the plan onto the grid
t = tt(0.06)
save("snap_tick", np.sin(2 * np.pi * 2200 * t) * env(t, 0.001, 0.012), 0.35)

# hammer blows (brighter than the hut's): wood + nail ring
for i, name in enumerate("abc"):
    t = tt(0.5)
    ring = bell(t, 1500 + i * 170, 0.08, ((1, 1.0), (2.4, 0.4), (3.9, 0.2))) * 0.5
    save(f"hammer_build_{name}", thud(0.5, 300 + i * 30, 120, 0.06) + ring, 0.6)

# a milestone: a deeper blow and a rising chime
t = tt(1.0)
save("milestone", thud(1.0, 120, 50, 0.2) + bell(t, 660, 0.5) * 0.25 + bell(np.maximum(t - 0.12, 0), 990, 0.45) * 0.2 * (t > 0.12), 0.7)

# the scaffold breaks apart: wood rattles and falls
t = tt(1.2)
rattle = np.zeros(len(t))
for _ in range(16):
    i = int(rng.uniform(0, 0.8) * RATE)
    k = tt(0.15)
    seg = np.sin(2 * np.pi * rng.uniform(250, 700) * k) * env(k, 0.001, 0.04)
    rattle[i:i + len(k)] += seg[:len(rattle) - i] * rng.uniform(0.4, 1.0)
save("scaffold_break", rattle + noise(len(t), 200, 3000) * env(t, 0.01, 0.3) * 0.4, 0.65)

# the consecration: a deep impact and a clear bell above it
t = tt(1.8)
boom = thud(1.8, 90, 34, 0.45) * 1.5
save("consecrate_hit", boom + noise(len(t), 40, 400) * env(t, 0.005, 0.5) * 0.5, 0.85)
t = tt(3.2)
save("consecrate_bell", bell(t, 523.25, 1.6) + bell(t, 784.0, 1.3) * 0.45 + bell(t, 1046.5, 1.0) * 0.2, 0.6)

# the pressure wave: an airy whoosh that runs outwards
t = tt(1.4)
sweep = noise(len(t), 200, 2400) * np.sin(np.pi * np.minimum(t / 1.4, 1)) ** 1.5
sweep += np.sin(2 * np.pi * np.cumsum(60 + 30 * t) / RATE) * env(t, 0.05, 0.5) * 0.6
save("wave", sweep, 0.7)

# plants torn out: a leafy rip with a soil pop
for i, name in enumerate("abc"):
    t = tt(0.4)
    rip = noise(len(t), 1200 + i * 300, 7000) * env(t, 0.004, 0.07)
    pop = np.sin(2 * np.pi * (180 - i * 20) * t) * env(t, 0.002, 0.05)
    save(f"uproot_{name}", rip + pop * 0.8, 0.45)

# the light floods out: a warm swelling chord
t = tt(2.2)
chord = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((261.6, 1.0), (329.6, 0.7), (392.0, 0.6), (523.3, 0.35)))
shimmer = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) for f in (1568, 1760, 2093)) * 0.08 * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * t))
save("light_flood", (chord + shimmer) * np.minimum(1, t / 0.5) * np.exp(-np.maximum(t - 0.6, 0) / 0.7), 0.5)

# the town's motif when you walk in: four soft bell notes
t = tt(3.0)
motif = np.zeros(len(t))
for at, f in ((0.0, 392.0), (0.28, 523.25), (0.56, 659.25), (0.95, 587.33)):
    i = int(at * RATE)
    k = tt(3.0 - at)
    motif[i:i + len(k)] += bell(k, f, 0.9, ((1, 1.0), (2.0, 0.25), (3.0, 0.1)))[:len(motif) - i]
save("town_motif", motif, 0.5)

# a new level: a peal of bells
t = tt(4.5)
peal = np.zeros(len(t))
for j, (at, f) in enumerate(((0.0, 523.25), (0.22, 659.25), (0.44, 783.99), (0.66, 1046.5), (1.1, 523.25), (1.1, 783.99), (1.1, 1046.5))):
    i = int(at * RATE)
    k = tt(4.5 - at)
    peal[i:i + len(k)] += bell(k, f, 1.4)[:len(peal) - i] * (0.8 if j < 4 else 0.6)
save("level_bells", peal + thud(4.5, 80, 36, 0.6) * 0.6, 0.7)

# the build plan's cards: paper rustle coming in, a flick when they turn
t = tt(0.25)
save("card_in", noise(len(t), 2000, 8000) * env(t, 0.01, 0.06), 0.3)
t = tt(0.12)
save("card_flip", noise(len(t), 3000, 9000) * env(t, 0.002, 0.025) + np.sin(2 * np.pi * 900 * t) * env(t, 0.001, 0.01) * 0.3, 0.3)

# the banner unrolls: cloth flapping and a wooden knock at the end
t = tt(0.9)
flap = noise(len(t), 300, 3000) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t)) * env(t, 0.05, 0.35)
knock = np.zeros(len(t))
k = tt(0.2)
i = int(0.55 * RATE)
knock[i:i + len(k)] = np.sin(2 * np.pi * 330 * k) * env(k, 0.001, 0.04)
save("banner_unroll", flap + knock * 0.8, 0.5)
print("town build sounds written to", OUT)
