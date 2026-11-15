#!/usr/bin/env python3
"""Synthesised placeholder sounds of Hallgrat's residents (docs/hallgrat_bewohner_konzept.md 10, 17) -> assets/audio/hallgrat_people/:
chisel_a..c (Odrik's chisel on stone, the steinsetzer's work), grind (one turn of Tamsa's grinding wheel against glass), sweep_a/b (a broom
of twigs over flagstones), lamp (Pim's lantern: a strike, a catch, a soft whoomp), polish (cloth squeaking on brass), serve (a clay mug set
down on wood), sing_0..2 (Hedda humming a short phrase), call_0..2 (a vendor's call over the market, vowel formants, no words) and murmur (the
evening crowd outside the inn, a seamless loop). Placeholders, no external recordings: `py -3 tools/audio_hallgrat_people.py`."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "hallgrat_people")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(77)


def save(name, x, peak=0.6):
    x = x / max(np.abs(x).max(), 1e-6) * peak
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def tt(seconds):
    return np.arange(int(R * seconds)) / R


def smooth(x, n):
    return np.convolve(x, np.ones(n) / n, mode="same")


def band(x, lo, hi):
    """A crude band pass: a difference of two moving averages."""
    return smooth(x, max(int(R / hi), 1)) - smooth(x, max(int(R / lo), 2))


def fade(x, a=0.005, b=0.02):
    n = len(x); e = np.ones(n)
    ia, ib = int(R * a), int(R * b)
    if ia: e[:ia] = np.linspace(0, 1, ia)
    if ib: e[-ib:] = np.linspace(1, 0, ib)
    return x * e


# chisel: a hard tick of iron on stone, a short bright ring and grit falling
for i, k in enumerate("abc"):
    r = np.random.default_rng(10 + i)
    t = tt(0.35)
    f = 2400 + 300 * i
    ring = sum(a * np.sin(2 * np.pi * f * m * t + r.uniform(0, 6)) * np.exp(-t * d) for m, a, d in ((1.0, 1.0, 38), (1.57, 0.5, 55), (2.3, 0.3, 70)))
    tick = r.standard_normal(len(t)) * np.exp(-t * 260)
    grit = band(r.standard_normal(len(t)), 1500, 7000) * np.exp(-t * 14) * (r.random(len(t)) ** 8) * 3.0
    thud = np.sin(2 * np.pi * 180 * t) * np.exp(-t * 60) * 0.5
    save("chisel_" + k, fade(ring * 0.35 + tick * 0.6 + grit * 0.3 + thud), 0.55)

# grind: one turn of the wheel, a whir that swells while the glass is pressed, with a thin singing edge
t = tt(0.86)
turn = 0.5 - 0.5 * np.cos(2 * np.pi * t / 0.86)
whir = band(rng.standard_normal(len(t)), 300, 2500) * (0.5 + 0.5 * np.sin(2 * np.pi * 23 * t))
sing = np.sin(2 * np.pi * (1850 + 40 * np.sin(2 * np.pi * 3 * t)) * t) * 0.12
save("grind", whir * (0.3 + 0.7 * turn) + sing * turn, 0.4)

# sweep: twigs dragged over stone, a soft rising-falling hiss
for i, k in enumerate("ab"):
    r = np.random.default_rng(30 + i)
    t = tt(0.45 + 0.05 * i)
    env = np.sin(np.pi * t / t[-1]) ** 1.5
    hiss = band(r.standard_normal(len(t)), 1200, 9000) * (0.6 + 0.4 * r.random(len(t)) ** 3)
    save("sweep_" + k, fade(hiss * env), 0.35)

# lamp: flint strike, the wick catching, a soft whoomp of the flame
t = tt(0.9)
strike = rng.standard_normal(len(t)) * np.exp(-t * 120) * (t < 0.06)
catch = band(rng.standard_normal(len(t)), 600, 4000) * np.exp(-np.abs(t - 0.18) * 30) * 0.4
whoomp = np.sin(2 * np.pi * (70 + 40 * np.exp(-(t - 0.2).clip(0) * 8)) * t) * np.exp(-(t - 0.2).clip(0) * 6) * (t > 0.2)
flutter = smooth(rng.standard_normal(len(t)), 60) * np.exp(-(t - 0.2).clip(0) * 4) * (t > 0.2) * 3
save("lamp", fade(strike * 0.5 + catch + whoomp * 0.6 + flutter * 0.3), 0.45)

# polish: cloth over brass, two squeaks
t = tt(0.5)
sq = np.zeros(len(t))
for at, f in ((0.05, 1300), (0.27, 1150)):
    s = (t - at).clip(0)
    e = np.sin(np.pi * np.clip(s / 0.16, 0, 1)) * (t > at)
    sq += np.sin(2 * np.pi * (f + 200 * s / 0.16) * s) * e * (0.6 + 0.4 * np.sin(2 * np.pi * 70 * s))
rub = band(rng.standard_normal(len(t)), 800, 5000) * 0.25
save("polish", fade(sq * 0.4 + rub * np.sin(np.pi * t / t[-1])), 0.3)

# serve: clay on wood, a knock with a hollow body and a little slosh
t = tt(0.4)
knock = np.sin(2 * np.pi * 320 * t) * np.exp(-t * 45) + 0.5 * np.sin(2 * np.pi * 510 * t) * np.exp(-t * 60)
slosh = band(rng.standard_normal(len(t)), 200, 1500) * np.exp(-np.abs(t - 0.08) * 25) * 0.6
save("serve", fade(knock + slosh + rng.standard_normal(len(t)) * np.exp(-t * 300) * 0.4), 0.5)


def voice(freqs, durs, formants, seed, breath=0.08, vib=5.5):
    """A sung or called line: a glottal pulse train through vowel formants, one note per duration."""
    r = np.random.default_rng(seed)
    parts = []
    for f0, d, (f1, f2) in zip(freqs, durs, formants):
        t = tt(d)
        f = f0 * (1 + 0.012 * np.sin(2 * np.pi * vib * t))
        phase = np.cumsum(2 * np.pi * f / R)
        # the vowel: harmonics near the two formants are louder
        y = sum(np.sin(h * phase) * (np.exp(-((h * f0 - f1) / 160) ** 2) + 0.5 * np.exp(-((h * f0 - f2) / 220) ** 2) + 0.05 / h) for h in range(1, 30))
        y += band(r.standard_normal(len(t)), 400, 4000) * breath
        env = np.minimum(1, t / 0.04) * np.minimum(1, (t[-1] - t) / 0.08)
        parts.append(y * env)
    return np.concatenate(parts)


A, O, E, U = (750, 1150), (500, 900), (450, 1900), (350, 800)
save("sing_0", fade(voice([220, 247, 262, 247, 220], [0.35, 0.3, 0.5, 0.3, 0.7], [U, U, O, U, U], 1, breath=0.05)), 0.32)
save("sing_1", fade(voice([196, 220, 247, 220], [0.4, 0.4, 0.6, 0.9], [U, O, O, U], 2, breath=0.05)), 0.32)
save("sing_2", fade(voice([262, 247, 220, 196, 220], [0.3, 0.3, 0.3, 0.5, 0.8], [O, U, U, O, U], 3, breath=0.05)), 0.32)
save("call_0", fade(voice([330, 392, 330], [0.25, 0.45, 0.35], [E, A, O], 4, breath=0.12, vib=4)), 0.42)
save("call_1", fade(voice([294, 349], [0.3, 0.7], [A, E], 5, breath=0.12, vib=4)), 0.42)
save("call_2", fade(voice([392, 330, 294], [0.2, 0.3, 0.6], [O, A, A], 6, breath=0.12, vib=4)), 0.42)

# murmur: many low voices talking at once, a slow swell, seamless (the last second is crossfaded into the first)
L = 6.0
t = tt(L + 1.0)
mur = np.zeros(len(t))
for k in range(9):
    r = np.random.default_rng(100 + k)
    f0 = r.uniform(95, 210)
    syll = (smooth(r.random(len(t)), int(R * 0.09)) > 0.5).astype(float)
    syll = smooth(syll, int(R * 0.03)) * (0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(0.1, 0.3) * t + r.uniform(0, 6)))
    f = f0 * (1 + 0.08 * smooth(r.standard_normal(len(t)), int(R * 0.2)) * 8)
    phase = np.cumsum(2 * np.pi * f / R)
    v = sum(np.sin(h * phase) * np.exp(-((h * f0 - r.choice([500, 700, 450])) / 300) ** 2) for h in range(1, 14))
    mur += v * syll * r.uniform(0.4, 1.0)
mur = smooth(mur, 4) + band(rng.standard_normal(len(t)), 200, 1200) * 0.08
n, x = int(R * L), int(R * 1.0)
loop = mur[:n].copy()
w = np.linspace(0, 1, x)
loop[:x] = mur[:x] * w + mur[n:n + x] * (1 - w)
save("murmur", loop, 0.3)
print("hallgrat people sounds written to", os.path.normpath(out))
