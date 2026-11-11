#!/usr/bin/env python3
"""Synthesized placeholders for the loot chests (docs/beutetruhen_konzept.md; numpy + stdlib wave). Writes assets/audio/chest/:
  latch, creak, thud_small          the Wurzelkiste: the rusty padlock springs, the old lid creaks, it falls back
  hold_rare, seal_hum, seal_crack   the Mondsiegeltruhe: a glassy hum under her hands, the moonstone cracking
  lid_rare, burst_rare               the lid flung open, a shimmering bloom of bells
  hold_legendary, chain_strain       the Glutreliquiar: chains grinding under the strain
  chain_snap, gem_swell              the links bursting, the sun heart swelling in the silence
  boom, choir, coins                 the lid blasted open: a deep impact, a warm chord, a shower of coins
  pop, sparkle, descend              a piece springing out, a rare one's glitter, a chest coming down in a pillar of light
Deterministic."""
from pathlib import Path
import wave

import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "chest"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = np.random.default_rng(23)


def T(sec):
    return np.arange(int(RATE * sec)) / RATE


def band(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return np.fft.irfft(spec * ((f >= lo) & (f <= hi)), len(x))


def save(name, sig, level=0.8):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * level
    fade = min(len(sig), 200)
    sig[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.int16(np.clip(sig, -1, 1) * 32767).tobytes())


def bell(t, f, decay, mod=1.4, depth=2.0):
    m = np.sin(2 * np.pi * f * mod * t) * depth * np.exp(-t * decay * 1.7)
    return np.sin(2 * np.pi * f * t + m) * np.exp(-t * decay)


def knock(t, f, decay):
    return np.sin(2 * np.pi * f * t) * np.exp(-t * decay) + band(rng.normal(size=len(t)), f, f * 6) * np.exp(-t * decay * 2.2) * 0.6


def place(dst, src, at):
    i = int(at * RATE)
    n = min(len(src), len(dst) - i)
    if n > 0:
        dst[i:i + n] += src[:n]


# --- Wurzelkiste
t = T(0.25)
save("latch", knock(t, 1900, 40) * 0.6 + knock(t, 2600, 55) * 0.4, 0.6)
t = T(0.7)
f0 = 220 + 140 * np.sin(np.pi * t / 0.7) ** 2  # a wooden creak: a rough sawtooth gliding up and down, gated in grains
saw = ((np.cumsum(f0) / RATE) % 1.0) * 2 - 1
grains = (np.sin(2 * np.pi * 38 * t) > -0.2).astype(float)
save("creak", band(saw * grains, 180, 3200) * np.minimum(1, t / 0.05) * np.exp(-t * 1.2), 0.6)
t = T(0.4)
save("thud_small", knock(t, 110, 14) + band(rng.normal(size=len(t)), 200, 1600) * np.exp(-t * 22) * 0.5, 0.7)

# --- Mondsiegeltruhe
t = T(1.0)
hum = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((392, 1.0), (587, 0.6), (784, 0.4), (1175, 0.25)))
save("hold_rare", hum * (t / 1.0) ** 1.5 * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * t)), 0.4)
t = T(0.7)
save("seal_hum", hum[: len(t)] * (t / 0.7) ** 2 * (0.6 + 0.4 * np.sin(2 * np.pi * 14 * t)) + band(rng.normal(size=len(t)), 3000, 8000) * (t / 0.7) ** 3 * 0.2, 0.5)
t = T(0.9)
crack = band(rng.normal(size=len(t)), 1800, 9000) * np.exp(-t * 18)
shards = np.zeros(len(t))
for k in range(14):
    place(shards, bell(T(0.5), rng.uniform(2200, 5200), 9), rng.uniform(0.02, 0.35))
save("seal_crack", crack + shards * 0.35, 0.8)
t = T(0.6)
save("lid_rare", knock(t, 170, 10) * 0.7 + band(rng.normal(size=len(t)), 400, 3000) * np.exp(-t * 8) * 0.3, 0.6)
t = T(2.4)
bloom = np.zeros(len(t))
for k, f in enumerate((523, 659, 784, 1047, 1319, 1568)):
    place(bloom, bell(T(2.0), f, 2.2), k * 0.06)
sweep = band(rng.normal(size=len(t)), 2500, 9000) * np.exp(-t * 2.5) * 0.25
save("burst_rare", bloom + sweep, 0.75)

# --- Glutreliquiar
t = T(1.6)
grind = np.zeros(len(t))
for k in range(30):  # links rubbing and clinking under strain, denser towards the end
    at = 1.55 * (k / 30) ** 0.7
    place(grind, knock(T(0.12), rng.uniform(900, 2400), 45) * rng.uniform(0.3, 0.8), at)
low = np.sin(2 * np.pi * (55 + 30 * t / 1.6) * t) * (t / 1.6) ** 2
save("hold_legendary", grind * 0.7 + low * 0.5, 0.6)
t = T(1.1)
save("chain_strain", grind[: len(t)] + np.sin(2 * np.pi * (48 + 40 * t) * t) * (t / 1.1) ** 2 * 0.6, 0.6)
t = T(1.0)
snap = band(rng.normal(size=len(t)), 600, 9000) * np.exp(-t * 14)
for k in range(10):
    place(snap, knock(T(0.3), rng.uniform(1300, 3200), 18) * 0.6, rng.uniform(0.05, 0.6))
save("chain_snap", snap, 0.85)
t = T(0.6)
save("gem_swell", sum(np.sin(2 * np.pi * f * t) for f in (220, 330, 440)) * (t / 0.6) ** 3 + band(rng.normal(size=len(t)), 4000, 9000) * (t / 0.6) ** 4 * 0.4, 0.5)
t = T(2.2)
save("boom", np.sin(2 * np.pi * (60 * np.exp(-t * 2) + 34) * t) * np.exp(-t * 2.6) + band(rng.normal(size=len(t)), 40, 900) * np.exp(-t * 5) * 0.8, 0.9)
t = T(3.4)
choir = np.zeros(len(t))
for f in (196, 247, 294, 392, 494, 587):
    vib = 0.006 * np.sin(2 * np.pi * 5.2 * t + f)
    choir += np.sin(2 * np.pi * f * t * (1 + vib)) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.7 * t + f))
choir *= np.minimum(1, t / 0.4) * np.exp(-t * 0.8)
save("choir", band(choir, 120, 4000) + band(rng.normal(size=len(t)), 3000, 8000) * np.exp(-t * 1.2) * 0.1, 0.55)
t = T(1.8)
coins = np.zeros(len(t))
for k in range(46):
    place(coins, bell(T(0.25), rng.uniform(3000, 6200), 26, 2.7, 1.2) * rng.uniform(0.3, 1.0), 1.5 * rng.uniform(0, 1) ** 1.6)
save("coins", coins, 0.6)

# --- shared
t = T(0.22)
save("pop", np.sin(2 * np.pi * (420 + 900 * t) * t) * np.exp(-t * 22) + band(rng.normal(size=len(t)), 1500, 6000) * np.exp(-t * 40) * 0.3, 0.55)
t = T(0.9)
sp = np.zeros(len(t))
for k in range(9):
    place(sp, bell(T(0.5), rng.uniform(2600, 5600), 8), k * 0.07)
save("sparkle", sp, 0.45)
t = T(1.0)
save("descend", band(rng.normal(size=len(t)), 1500, 9000) * (t / 1.0) ** 1.5 * 0.5 + np.sin(2 * np.pi * (900 - 600 * t) * t) * (t / 1.0) * 0.4, 0.55)
print("chest sounds written to", OUT)
