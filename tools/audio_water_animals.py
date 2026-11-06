#!/usr/bin/env python3
"""Quiet synthesized calls of the water animals (numpy + stdlib, no recordings): frog croak (two pulsed throat notes), duck quack (nasal
formants, falling pitch), kingfisher call (two sharp high pings), heron croak (low rasping 'fraank'). Two variants each, deterministic.
Writes assets/audio/wildlife/{frog,duck,kingfisher,heron}_{0,1}.wav"""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / 'assets/audio/wildlife'
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050


def save(name, signal):
    pcm = np.int16(signal / (np.max(np.abs(signal)) + 1e-8) * 0.55 * 32767)
    with wave.open(str(OUT / name), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def voice(f, formants, rng, noise=0.1):
    phase = np.cumsum(f) * 2 * np.pi / RATE
    sig = np.zeros_like(f)
    base = float(np.mean(f))
    for h in range(1, 20):
        sig += (0.05 / h + sum(np.exp(-0.5 * ((h * base - fm) / (fm * 0.25)) ** 2) for fm in formants) / (1 + h * 0.15)) * np.sin(phase * h)
    return sig + noise * np.convolve(rng.normal(0, 1, len(f)), [0.25, 0.5, 0.25], mode='same')


for v in range(2):
    rng = np.random.default_rng(31 + v)
    # frog: two throat pulses, a bubbling buzz
    t = np.arange(int(RATE * (0.5 + 0.1 * v))) / RATE
    f = 150 + 30 * v + 30 * np.sin(t * 7)
    pulse = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * (38 + 6 * v) * t))) * (np.sin(np.pi * np.minimum(1, t / t[-1] * 1.0)) ** 0.5)
    note = voice(f, [380, 900], rng, 0.04) * pulse
    env = np.where(t < 0.2, np.sin(np.pi * t / 0.2) ** 0.8, 0) + np.where(t > 0.26, np.sin(np.pi * (t - 0.26) / (t[-1] - 0.26)) ** 0.8, 0)
    save(f'frog_{v}.wav', note * env)
    # duck: a short nasal quack with falling pitch
    t = np.arange(int(RATE * 0.26)) / RATE
    u = t / t[-1]
    f = (520 - 230 * u) * (1 + 0.06 * v)
    quack = voice(f, [900, 1900, 2800], rng, 0.08) * np.sin(np.pi * u) ** 0.6 * np.minimum(1, u * 25)
    save(f'duck_{v}.wav', quack * (1 + 0.4 * np.sin(t * 2 * np.pi * 60)))
    # kingfisher: two sharp pings, the second one higher
    t = np.arange(int(RATE * 0.34)) / RATE
    sig = np.zeros_like(t)
    for start, freq in ((0.0, 4100 + 200 * v), (0.15, 4600 + 200 * v)):
        m = (t >= start) & (t < start + 0.1)
        tt = t[m] - start
        sig[m] += np.sin(2 * np.pi * (freq + 500 * tt / 0.1) * tt) * np.exp(-tt * 38) + 0.3 * np.sin(2 * np.pi * freq * 2 * tt) * np.exp(-tt * 60)
    save(f'kingfisher_{v}.wav', sig)
    # heron: a rasping, low 'fraank'
    t = np.arange(int(RATE * 0.7)) / RATE
    u = t / t[-1]
    f = 110 * (1 + 0.25 * np.sin(np.pi * u) - 0.2 * u) + np.interp(t, np.linspace(0, t[-1], 30), rng.normal(0, 8, 30))
    croak = voice(f, [500, 1100, 2000], rng, 0.2) * np.sin(np.pi * u) ** 0.7 * np.minimum(1, u * 14) * (0.75 + 0.25 * np.sin(t * 2 * np.pi * 40))
    save(f'heron_{v}.wav', croak)
print('Wrote 8 quiet water-animal call samples')
