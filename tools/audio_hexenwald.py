#!/usr/bin/env python3
"""Synthesised placeholder sounds of the Hexenwald's mist (docs/hexenwald_nebel_konzept.md) -> assets/audio/hexenwald/ (numpy + stdlib, deterministic):
whisper_a/b/c (breathy voices without words, from the side), puff (a dull inward suck and a soft burst: a hallucination falls apart),
clear (a rising glassy breath: the Ohrringe der Klarheit push the mist back),
creak_a/b/c (dead wood under strain: the Bleichbaum jerks, FirTree `twitch`; docs/hexenwald_leben_konzept.md),
toad_a/b (a toad's low, burring call: a short train of throaty pulses, TinyWildlife)."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "hexenwald")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(31)


def T(sec): return np.arange(int(R * sec)) / R


def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.6
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")


def breath(sec, formant, wobble):
    """Band-limited noise shaped like a mouth: a moving formant, syllables as slow lumps."""
    t = T(sec)
    n = rng.standard_normal(len(t))
    band = lowpass(n, 6) - lowpass(n, 40)
    f = formant * (1.0 + 0.25 * np.sin(2 * np.pi * wobble * t + rng.uniform(0, 6)))
    voiced = band * (0.55 + 0.45 * np.sin(2 * np.pi * np.cumsum(f) / R))
    syll = np.clip(np.sin(2 * np.pi * (2.6 + wobble) * t + rng.uniform(0, 6)), 0, 1) ** 1.5
    return voiced * syll * np.sin(np.pi * t / sec) ** 1.5


for name, sec, formant, wobble in (("whisper_a", 1.5, 900, 1.3), ("whisper_b", 2.1, 1300, 0.8), ("whisper_c", 1.1, 700, 2.1)):
    save(name, breath(sec, formant, wobble))

t = T(0.7)
suck = lowpass(rng.standard_normal(len(t)), 30) * np.clip(t / 0.32, 0, 1) ** 3 * (t < 0.32)
burst = lowpass(rng.standard_normal(len(t)), 9) * np.exp(-np.clip(t - 0.32, 0, 9) * 9) * (t >= 0.32)
thud = np.sin(2 * np.pi * 62 * t) * np.exp(-np.clip(t - 0.32, 0, 9) * 14) * (t >= 0.32)
save("puff", suck * 1.4 + burst * 0.7 + thud * 0.9)

t = T(1.6)
sweep = np.sin(2 * np.pi * np.cumsum(300 + 900 * (t / 1.6) ** 2) / R) * 0.25
air = (lowpass(rng.standard_normal(len(t)), 4) - lowpass(rng.standard_normal(len(t)), 30)) * 0.8
save("clear", (sweep + air) * np.sin(np.pi * t / 1.6) ** 2 + np.sin(2 * np.pi * 1760 * t) * np.exp(-np.clip(t - 1.0, 0, 9) * 5) * (t > 1.0) * 0.3)


def creak(sec, f0, f1, body, seed):
    """Stick-slip friction: a train of clicks whose rate glides and stutters, rung through a hollow wooden body."""
    r = np.random.default_rng(seed)
    t = T(sec)
    rate = f0 + (f1 - f0) * (np.sin(np.pi * t / sec * 0.9) ** 2) + lowpass(r.standard_normal(len(t)), 900) * 40
    phase = np.cumsum(np.maximum(rate, 20) / R)
    clicks = np.diff(np.floor(phase), prepend=0.0) * (0.6 + 0.4 * r.random(len(t)))
    ir_t = np.arange(int(R * 0.03)) / R
    ir = sum(np.sin(2 * np.pi * f * ir_t) * np.exp(-ir_t * d) for f, d in ((body, 160), (body * 2.3, 260), (body * 0.55, 120)))
    x = np.convolve(clicks, ir)[: len(t)]
    env = np.clip(t / 0.06, 0, 1) * np.clip((sec - t) / 0.25, 0, 1) * (0.7 + 0.3 * np.sin(2 * np.pi * 3.1 * t))
    return lowpass(x, 3) * env


for name, sec, f0, f1, body, seed in (("creak_a", 0.9, 55, 120, 420, 7), ("creak_b", 1.3, 80, 45, 310, 8), ("creak_c", 0.6, 110, 160, 520, 9)):
    save(name, creak(sec, f0, f1, body, seed))


def croak(pulses, f0, gap, seed):
    """A toad: a train of short throaty pulses, each a buzz rung through a low formant, the last ones fading."""
    r = np.random.default_rng(seed)
    sec = pulses * gap + 0.12
    t = T(sec)
    x = np.zeros(len(t))
    for k in range(pulses):
        start = int((k * gap + r.uniform(0, 0.008)) * R)
        n = int(0.055 * R)
        tt = np.arange(n) / R
        f = f0 * (1.0 + 0.08 * np.sin(2 * np.pi * 9 * tt)) * r.uniform(0.96, 1.04)
        buzz = np.sign(np.sin(2 * np.pi * np.cumsum(f) / R)) * 0.6 + np.sin(2 * np.pi * np.cumsum(f * 2.0) / R) * 0.4
        env = np.sin(np.pi * tt / 0.055) ** 2 * (1.0 - 0.45 * k / pulses)
        seg = lowpass(buzz * env, 7)
        x[start:start + n] += seg[: len(x) - start]
    return x


for name, pulses, f0, gap, seed in (("toad_a", 5, 118, 0.07, 21), ("toad_b", 8, 96, 0.062, 22)):
    save(name, croak(pulses, f0, gap, seed))
print("hexenwald sounds written")
