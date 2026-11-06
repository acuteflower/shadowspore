#!/usr/bin/env python3
"""Fishing sounds, synthesised placeholders (numpy + wave): assets/audio/fishing/*.wav, 22050 Hz mono.
cast (a thin whip through the air), splash (float lands), tap (nibble), bite (hollow plop), snap (line breaks),
landed (water breaks, soft chime), creak (a loop: the line under load, the game raises its pitch with the tension)."""
import pathlib
import wave

import numpy as np

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "fishing"
SR = 22050
rng = np.random.default_rng(7)


def save(name, data):
    OUT.mkdir(parents=True, exist_ok=True)
    data = data / max(1e-6, np.max(np.abs(data))) * 0.8
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


t = t_axis(0.28)
noise = rng.standard_normal(t.size)
sweep = np.sin(2 * np.pi * (900 + 2600 * t / t[-1] ** 1) * t)
save("cast", (lowpass(noise, 0.5) * 0.6 + sweep * 0.25) * np.sin(np.pi * t / t[-1]) ** 1.5)

t = t_axis(0.35)
save("splash", lowpass(rng.standard_normal(t.size), 0.35) * env(t, 0.004, 0.07) + np.sin(2 * np.pi * 180 * t) * env(t, 0.003, 0.05) * 0.5)

t = t_axis(0.12)
save("tap", np.sin(2 * np.pi * 540 * t) * env(t, 0.002, 0.02) + lowpass(rng.standard_normal(t.size), 0.5) * env(t, 0.001, 0.01) * 0.3)

t = t_axis(0.4)
save("bite", np.sin(2 * np.pi * (140 - 60 * t) * t) * env(t, 0.003, 0.09) + lowpass(rng.standard_normal(t.size), 0.25) * env(t, 0.002, 0.06) * 0.6)

t = t_axis(0.3)
save("snap", rng.standard_normal(t.size) * env(t, 0.001, 0.012) + np.sin(2 * np.pi * 2400 * t) * env(t, 0.001, 0.05) * 0.4)

t = t_axis(0.8)
chime = sum(np.sin(2 * np.pi * f * t) * env(t, 0.01, 0.25 / (i + 1)) for i, f in enumerate((660, 990, 1320)))
save("landed", chime * 0.5 + lowpass(rng.standard_normal(t.size), 0.3) * env(t, 0.002, 0.1) * 0.5)

t = t_axis(1.0)  # loops: whole periods only
base = 310.0
creak = np.sin(2 * np.pi * base * t + 2.0 * np.sin(2 * np.pi * 7 * t)) + 0.5 * np.sin(2 * np.pi * base * 2 * t + 1.5 * np.sin(2 * np.pi * 5 * t))
creak += lowpass(rng.standard_normal(t.size), 0.08) * 0.8
save("creak", creak * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t)))
print("written", sorted(p.name for p in OUT.glob("*.wav")))
