#!/usr/bin/env python3
"""Swimming sounds, synthesised placeholders (numpy + wave): assets/audio/swim/*.wav, 22050 Hz mono.
dive_big (head-first dive), dive_small (stepping into deep water), stroke_a/b (an arm pulling through the water, a little different each),
kick (leg splash), breath (a breath at the surface), bubble, exit (climbing out, water running off), drip, shake (shaking water out of hair and coat)."""
import pathlib
import wave

import numpy as np

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "swim"
SR = 22050
rng = np.random.default_rng(11)


def save(name, data, peak=0.8):
    OUT.mkdir(parents=True, exist_ok=True)
    data = data / max(1e-6, np.max(np.abs(data))) * peak
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((data * 32767).astype(np.int16).tobytes())


def t_axis(sec):
    return np.linspace(0, sec, int(SR * sec), endpoint=False)


def lowpass(x, k):
    out = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += (v - acc) * k
        out[i] = acc
    return out


def env(t, attack, decay):
    return np.minimum(t / attack, 1.0) * np.exp(-t / decay)


def noise(t):
    return rng.standard_normal(t.size)


def gurgle(t, base, depth, rate):
    """Bubbly water: a few short falling sine blips."""
    out = np.zeros_like(t)
    for _ in range(int(rate * t[-1])):
        start = rng.uniform(0, t[-1] * 0.8)
        f0 = base * rng.uniform(0.7, 1.6)
        dt = np.clip(t - start, 0, None)
        out += np.sin(2 * np.pi * (f0 + depth * dt) * dt) * env(dt, 0.002, 0.03) * (t >= start) * rng.uniform(0.3, 1.0)
    return out


t = t_axis(0.9)
body = lowpass(noise(t), 0.18) * env(t, 0.005, 0.22)
crown = lowpass(noise(t), 0.5) * env(t, 0.004, 0.08) * 0.5
thump = np.sin(2 * np.pi * (90 - 40 * t) * t) * env(t, 0.004, 0.12)
save("dive_big", body * 1.0 + crown + thump * 0.8 + gurgle(t, 500, 1800, 14) * 0.25)

t = t_axis(0.55)
save("dive_small", lowpass(noise(t), 0.25) * env(t, 0.006, 0.12) + np.sin(2 * np.pi * (140 - 50 * t) * t) * env(t, 0.004, 0.07) * 0.5 + gurgle(t, 600, 1500, 8) * 0.2)

for name, k, f in (("stroke_a", 0.2, 300), ("stroke_b", 0.26, 380)):
    t = t_axis(0.34)
    swoosh = lowpass(noise(t), k) * np.sin(np.pi * np.clip(t / 0.3, 0, 1)) ** 2
    save(name, swoosh * 0.7 + gurgle(t, f, 1200, 10) * 0.25, 0.5)

t = t_axis(0.22)
save("kick", lowpass(noise(t), 0.4) * env(t, 0.003, 0.05) + np.sin(2 * np.pi * 160 * t) * env(t, 0.003, 0.04) * 0.3, 0.55)

t = t_axis(0.42)
breath = lowpass(noise(t), 0.12) * np.sin(np.pi * np.clip(t / 0.4, 0, 1)) * (1 + 0.3 * np.sin(2 * np.pi * 7 * t))
save("breath", breath, 0.45)

t = t_axis(0.3)
save("bubble", gurgle(t, 700, 2500, 6) + 0.0, 0.5)

t = t_axis(1.1)
run = lowpass(noise(t), 0.3) * env(t, 0.05, 0.4) * (0.5 + 0.5 * np.sin(2 * np.pi * 6 * t) ** 2)
save("exit", run * 0.8 + gurgle(t, 450, 900, 10) * 0.3 + lowpass(noise(t), 0.5) * env(t, 0.003, 0.05) * 0.4, 0.6)

t = t_axis(0.18)
save("drip", np.sin(2 * np.pi * (900 + 1800 * t) * t) * env(t, 0.001, 0.03), 0.3)

t = t_axis(0.8)
shake = lowpass(noise(t), 0.35) * np.abs(np.sin(2 * np.pi * 9 * t)) * np.exp(-t / 0.5)
save("shake", shake + gurgle(t, 800, 2000, 12) * 0.15, 0.6)
print("swim sounds written to", OUT)
