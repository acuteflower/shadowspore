#!/usr/bin/env python3
"""Synthesised placeholder sounds of the alchemy (docs/alchemie_konzept.md) -> assets/audio/alchemy/ (numpy + stdlib, deterministic):
cork (a thumb flicks the cork: a wet pop), gulp (two quick swallows), glass (the empty vial shatters on the ground: a tinkle of shards),
heal (a soft rising rose chime: Wundtau takes hold), stamina (a crackle of embers and a warm swell: Glutatem), deny (a dull wooden tick: a pause runs),
plop (an ingredient drops into Esma's cauldron), bubble (the brew boils up: a few deep bubbles), brewed (the potions are ready: a glassy three-note chord),
moon (a silvery shimmer on top: the full moon stirred along)."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "alchemy")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(73)


def T(sec): return np.arange(int(R * sec)) / R


def save(name, x, peak=0.6):
    x = x / max(np.abs(x).max(), 1e-6) * peak
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def place(buf, x, at):
    i = int(R * at); n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n]


def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")


def bell(f, sec, decay):
    t = T(sec)
    return (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 12)) * np.exp(-t * decay) * np.minimum(1, t * 400)


def sweep(f0, f1, sec, decay):
    t = T(sec); f = f0 * (f1 / f0) ** (t / sec)
    return np.sin(np.cumsum(f) * 2 * np.pi / R) * np.exp(-t * decay) * np.minimum(1, t * 300)


def bubble(f, sec=0.09):
    return sweep(f, f * 2.3, sec, 26.0)


# cork: a short click plus a rising wet pop
x = np.zeros(int(R * 0.25))
t = T(0.012)
place(x, rng.standard_normal(len(t)) * np.exp(-t * 400) * 0.6, 0.0)
place(x, sweep(380, 1100, 0.07, 30.0), 0.006)
save("cork", x)

# gulp: two swallows, low wet sweeps with a throat thump
x = np.zeros(int(R * 0.45))
for at, f in ((0.0, 210), (0.19, 180)):
    place(x, sweep(f, f * 0.55, 0.12, 18.0) * 0.9, at)
    t = T(0.03)
    place(x, lowpass(rng.standard_normal(len(t)), 30) * np.exp(-t * 120) * 2.0, at + 0.05)
save("gulp", x)

# glass: many tiny high bells scattered over 0.35 s, a crack at the start
x = np.zeros(int(R * 0.6))
t = T(0.02)
place(x, np.diff(rng.standard_normal(len(t)), prepend=0) * np.exp(-t * 250) * 0.8, 0.0)
for k in range(14):
    place(x, bell(rng.uniform(3200, 7200), 0.25, rng.uniform(18, 30)) * rng.uniform(0.15, 0.45), rng.uniform(0.0, 0.3) ** 1.6)
save("glass", x, 0.5)

# heal: a rising rose chime
x = np.zeros(int(R * 1.0))
for k, f in enumerate((660, 880, 1320)):
    place(x, bell(f, 0.8, 5.5) * (0.5 - k * 0.08), k * 0.07)
t = T(0.6)
place(x, np.sin(2 * np.pi * 440 * t) * np.sin(np.pi * t / 0.6) * 0.15, 0.0)
save("heal", x)

# stamina: ember crackle and a warm swell
x = np.zeros(int(R * 1.0))
t = T(0.8)
place(x, (np.sin(2 * np.pi * 220 * t) + 0.5 * np.sin(2 * np.pi * 330 * t)) * np.sin(np.pi * t / 0.8) ** 2 * 0.25, 0.0)
for k in range(18):
    tt = T(0.012)
    place(x, rng.standard_normal(len(tt)) * np.exp(-tt * 300) * rng.uniform(0.2, 0.6), rng.uniform(0.0, 0.7))
save("stamina", x)

# deny: a dull wooden tick
x = np.zeros(int(R * 0.15))
t = T(0.08)
place(x, np.sin(2 * np.pi * 300 * t) * np.exp(-t * 60) + lowpass(rng.standard_normal(len(t)), 8) * np.exp(-t * 120) * 0.6, 0.0)
save("deny", x, 0.4)

# plop: a herb into the cauldron
x = np.zeros(int(R * 0.35))
place(x, sweep(240, 120, 0.08, 25.0), 0.0)
place(x, bubble(300) * 0.6, 0.07)
save("plop", x)

# bubble: the brew boils up
x = np.zeros(int(R * 1.2))
for k in range(16):
    place(x, bubble(rng.uniform(110, 260), rng.uniform(0.06, 0.12)) * rng.uniform(0.3, 0.8), rng.uniform(0.0, 1.05))
save("bubble", x)

# brewed: a glassy chord
x = np.zeros(int(R * 1.6))
for k, f in enumerate((784, 988, 1175, 1568)):
    place(x, bell(f, 1.4, 3.2) * (0.5 - k * 0.07), k * 0.09)
save("brewed", x)

# moon: a silvery shimmer
x = np.zeros(int(R * 1.6))
for k in range(9):
    place(x, bell(2093 * 2 ** (k / 12.0 * 2), 1.0, 4.0) * 0.18, k * 0.08)
save("moon", x, 0.4)
print("ok")

# ashen: a low rush of heat, embers popping and a hissing settle (Aschenhaut closes round her)
x = np.zeros(int(R * 1.1))
t = T(0.9)
place(x, lowpass(rng.standard_normal(len(t)), 40) * np.sin(np.pi * t / 0.9) ** 1.5 * 1.4, 0.0)
place(x, np.sin(2 * np.pi * 110 * t) * np.sin(np.pi * t / 0.9) * 0.3, 0.0)
for k in range(14):
    tt = T(0.01)
    place(x, rng.standard_normal(len(tt)) * np.exp(-tt * 400) * rng.uniform(0.3, 0.8), rng.uniform(0.1, 0.9))
save("ashen", x)

# clarity: a clear glassy ring that opens upwards (the head clears)
x = np.zeros(int(R * 1.2))
for k, f in enumerate((1047, 1568, 2093, 3136)):
    place(x, bell(f, 1.0, 4.5) * (0.5 - k * 0.07), k * 0.05)
t = T(0.5)
place(x, np.sin(2 * np.pi * (700 + 900 * t / 0.5) * t) * np.sin(np.pi * t / 0.5) * 0.12, 0.0)
save("clarity", x)

# wisp: a breathy whistle that rises and flutters into a thin shimmer (a small light is born)
x = np.zeros(int(R * 1.2))
t = T(0.8)
fl = 1.0 + 0.02 * np.sin(2 * np.pi * 9 * t)
place(x, np.sin(2 * np.pi * np.cumsum((520 + 700 * t / 0.8) * fl) / R) * np.sin(np.pi * t / 0.8) ** 2 * 0.4, 0.0)
place(x, lowpass(rng.standard_normal(len(t)), 6) * np.sin(np.pi * t / 0.8) ** 2 * 0.08, 0.0)
for k in range(9):
    place(x, bell(rng.uniform(2400, 5200), 0.4, 14.0) * rng.uniform(0.08, 0.25), 0.25 + rng.uniform(0.0, 0.6))
save("wisp", x)
