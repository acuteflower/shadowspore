#!/usr/bin/env python3
"""Synthesised placeholder sounds of the Himmelsriss (docs/rissklinge.md) -> assets/audio/rift/. Deterministic. Needs numpy.
swing (a diagonal slash: heavy air with a dark tail), line (the thrust's lane of light tears open: a falling filtered rip with crackle), volley (the feathers
leave the blade: a dry crack, a rush of air and a quick flutter)."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "rift")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(41)


def T(sec): return np.arange(int(R * sec)) / R


def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.7
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")


def noise(sec): return rng.standard_normal(int(R * sec))


def bell(f, t, decay):
    return np.sin(2 * np.pi * f * t) * np.exp(-t * decay) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * decay * 1.8)


def place(buf, x, at):
    i = int(R * at); n = min(len(x), len(buf) - i); buf[i:i + n] += x[:n]


def feathers(sec, density, bright):
    """A dry rustle: many tiny soft ticks with a falling envelope."""
    n = int(R * sec); buf = np.zeros(n)
    for _ in range(int(density * sec)):
        at = int(n * rng.random() ** 1.4)
        k = int(R * rng.uniform(0.004, 0.012))
        if at + k < n:
            buf[at:at + k] += np.diff(lowpass(rng.standard_normal(k + 1), 2)) * rng.random() * bright * np.exp(-np.arange(k) / (R * 0.004))
    return buf * np.exp(-T(sec) * 3.0)


# swing: heavy air, dark tail
t = T(0.55)
air = lowpass(noise(0.55), 10) * np.sin(np.pi * np.minimum(t / 0.55, 1.0)) ** 1.5 * 1.2
tone = np.sin(2 * np.pi * (180 - 90 * t / 0.55) * t) * np.exp(-t * 6.0) * 0.5
save("swing", air + tone)

# line: a lane of light tears open
t = T(0.7)
freq = 3200 - 2600 * np.minimum(t / 0.45, 1.0)
rip = np.sin(2 * np.pi * np.cumsum(freq) / R) * np.exp(-t * 5.5) * 0.35
hiss = np.diff(lowpass(noise(0.7), 2), prepend=0) * np.exp(-t * 7.0) * 1.1
x = rip + hiss * (1 - np.exp(-t * 700))
place(x, feathers(0.5, 320, 3.0) * 0.5, 0.04)
place(x, np.sin(2 * np.pi * 70 * T(0.5)) * np.exp(-T(0.5) * 9) * 0.5, 0.0)
save("line", x)

# volley: the feathers leave the blade: a dry crack, a rush of air, then a quick flutter of many tiny ticks flying away
t = T(0.6)
crack = np.diff(lowpass(noise(0.6), 2), prepend=0) * np.exp(-t * 45) * 1.2 * (1 - np.exp(-t * 900))
rush = lowpass(noise(0.6), 5) * np.sin(np.pi * np.minimum(t / 0.6, 1.0)) ** 1.2 * 0.5
whistle = np.sin(2 * np.pi * (1800 + 1400 * t / 0.6) * t) * np.exp(-t * 9) * 0.12
x = crack + rush + whistle
place(x, feathers(0.5, 420, 3.5) * 0.7, 0.03)
place(x, bell(880, T(0.35), 12.0) * 0.18, 0.02)
save("volley", x)
print("wrote", out)
