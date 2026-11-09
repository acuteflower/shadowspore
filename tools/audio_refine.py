#!/usr/bin/env python3
"""Synthesised placeholder sounds of refining (Torben's forge, docs/refinement_konzept.md) -> assets/audio/refine/:
hand_in (the weapon laid on the anvil: a clank and a sizzle), ember (the build-up while the iron heats: a swelling flare), success (a hammer ring and three rising bell notes),
perfect (the same, longer, with a shimmering chord: a milestone or +15), fail (a dull thud, a crack, a hiss, a sinking tone). Deterministic."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "refine")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(11)

def T(sec): return np.arange(int(R * sec)) / R

def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.75
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def lowpass(x, k):
    return np.convolve(x, np.ones(k) / k, mode="same")

def bell(f, t, decay):
    return np.sin(2 * np.pi * f * t) * np.exp(-t * decay) + 0.4 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * decay * 1.8) + 0.2 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * decay * 3.0)

def clang(t, base, decay):
    parts = [1.0, 2.32, 4.25, 6.63, 9.38]
    return sum(np.sin(2 * np.pi * base * p * t + i) * np.exp(-t * decay * (1 + 0.5 * i)) / (1 + i * 0.6) for i, p in enumerate(parts))

def place(buf, x, at):
    i = int(R * at)
    n = min(len(x), len(buf) - i)
    buf[i:i + n] += x[:n]

# hand_in: a clank of iron on iron, then the sizzle of a hot piece taking the cold weapon
t = T(0.7)
hand = np.zeros(len(t))
place(hand, clang(T(0.5), 520, 9) * (1 - np.exp(-T(0.5) * 900)), 0.0)
hiss = lowpass(rng.standard_normal(len(t)), 5) * np.exp(-t * 6.0) * 0.35
hand += np.where(t > 0.06, hiss, 0)
save("hand_in", hand)

# ember: the iron heats up, a flare that swells and tightens
t = T(0.95)
swell = (t / t[-1]) ** 2.2
noise = lowpass(rng.standard_normal(len(t)), 9) * swell
rumble = np.sin(2 * np.pi * (70 + 130 * swell) * t) * swell * 0.7
crackle = (rng.random(len(t)) > 0.9985).astype(float) * rng.standard_normal(len(t)) * 2.0 * (0.2 + swell)
save("ember", noise + rumble + lowpass(crackle, 3))

# success: the hammer rings once, then three bright bell notes rise
t = T(1.5)
ok = np.zeros(len(t))
place(ok, clang(T(0.6), 880, 7) * (1 - np.exp(-T(0.6) * 800)), 0.0)
for i, f in enumerate((1175, 1568, 2093)):
    place(ok, bell(f, T(1.1), 5.0) * 0.8, 0.18 + i * 0.13)
save("success", ok)

# perfect: success with a long shimmering chord under it
t = T(2.6)
pf = np.zeros(len(t))
place(pf, clang(T(0.8), 740, 6) * (1 - np.exp(-T(0.8) * 800)), 0.0)
for i, f in enumerate((880, 1175, 1568, 2093, 2637)):
    place(pf, bell(f, T(1.8), 3.0) * 0.8, 0.14 + i * 0.11)
shimmer = sum(np.sin(2 * np.pi * f * t + np.sin(2 * np.pi * 5.0 * t) * 0.6) for f in (392, 494, 587, 784)) * np.exp(-t * 1.5) * (1 - np.exp(-t * 6)) * 0.5
pf += shimmer
save("perfect", pf)

# fail: a dull thud, the crack of cooling metal, a hiss and a tone that sinks
t = T(1.3)
bad = np.zeros(len(t))
thud = np.sin(2 * np.pi * (95 - 35 * np.minimum(T(0.4) / 0.4, 1)) * T(0.4)) * np.exp(-T(0.4) * 11)
place(bad, thud * 1.2, 0.0)
crack = lowpass(rng.standard_normal(int(R * 0.06)), 2) * np.exp(-T(0.06) * 60)
place(bad, crack * 1.4, 0.07)
place(bad, lowpass(rng.standard_normal(int(R * 0.9)), 4) * np.exp(-T(0.9) * 4.0) * 0.45, 0.12)
tt = T(1.0)
place(bad, np.sin(2 * np.pi * (330 - 140 * tt) * tt) * np.exp(-tt * 3.5) * 0.35, 0.1)
save("fail", bad)
print("wrote", out)
