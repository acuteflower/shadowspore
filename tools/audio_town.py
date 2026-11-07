#!/usr/bin/env python3
"""Synthesized placeholders for the town additions (docs/town_ausbau.md; numpy + stdlib wave): a lamp being lit, the market flap opening and shutting, the spark where the town's
light turns a creature back, a low hum of the light when a raid gathers, a quiet murmur for the fire circle. Writes assets/audio/town/*.wav deterministically."""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "town"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = np.random.default_rng(91)


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


# a lamp lit: a soft whoomp (low sine swelling), then a crackle of sparks
t = tt(1.1)
whoomp = np.sin(2 * np.pi * (70 + 40 * np.exp(-t * 6)) * t) * env(t, 0.03, 0.22)
noise = band(rng.normal(0, 1, len(t)), 800, 6000)
sparks = noise * (rng.random(len(t)) > 0.994) * 4.0
sparks = np.convolve(sparks, np.exp(-np.arange(200) / 30.0), "same") * np.exp(-t / 0.5)
hiss = band(rng.normal(0, 1, len(t)), 1500, 5000) * env(t, 0.12, 0.35) * 0.25
save("lamp_light", whoomp * 1.2 + sparks * 0.5 + hiss, 0.7)

# the flap: wood creak with a clack at the end (open) / a thud (shut)
def creak(length, f0, f1, seed):
    r = np.random.default_rng(seed)
    t = tt(length)
    freq = f0 + (f1 - f0) * (t / t[-1]) + 12 * np.sin(t * 19)
    stick = (r.random(len(t)) > 0.996).astype(float)
    pulses = np.convolve(stick, np.exp(-np.arange(260) / 35.0), "same")
    tone = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * (0.5 + 0.5 * np.sin(2 * np.pi * 11 * t))
    sig = band(tone + pulses * 4 + r.normal(0, 0.12, len(t)), 200, 1700)
    return sig * np.minimum(1, t / 0.06) * np.minimum(1, (t[-1] - t) / 0.12)


def knock(length, f, decay, seed):
    r = np.random.default_rng(seed)
    t = tt(length)
    return (np.sin(2 * np.pi * f * t) + band(r.normal(0, 1, len(t)), 150, 900) * 0.8) * np.exp(-t / decay)


c = creak(0.55, 260, 340, 4)
k = knock(0.25, 160, 0.05, 5)
save("shutter_open", np.concatenate([c, k * 0.8]), 0.6)
c = creak(0.5, 340, 230, 6)
k = knock(0.3, 110, 0.07, 7)
save("shutter_close", np.concatenate([c, k * 1.3]), 0.65)

# a spark where the light turns a creature back: a bright crackle burst
t = tt(0.5)
burst = band(rng.normal(0, 1, len(t)), 1800, 9000) * (rng.random(len(t)) > 0.985)
burst = np.convolve(burst, np.exp(-np.arange(120) / 14.0), "same") * np.exp(-t / 0.18)
ping = np.sin(2 * np.pi * 1400 * t) * env(t, 0.002, 0.07) * 0.3
save("light_touch", burst * 3 + ping, 0.5)

# the hum of the light when a raid gathers (3 s, seamless: whole cycles)
t = tt(3.0)
hum = np.sin(2 * np.pi * 55 * t) + 0.5 * np.sin(2 * np.pi * 110 * t + 0.6) + 0.25 * np.sin(2 * np.pi * 165 * t)
hum *= 0.7 + 0.3 * np.sin(2 * np.pi * 2 * t)
save("light_hum", hum, 0.35)

# the fire circle: a warm chord swelling and fading, like a breath of heat
t = tt(2.2)
chord = sum(np.sin(2 * np.pi * f * t + p) for f, p in ((196.0, 0.0), (246.9, 0.4), (293.7, 0.9), (392.0, 1.3)))
save("warmth", chord * np.sin(np.pi * t / t[-1]) ** 2 * 0.3, 0.35)
print("written", sorted(p.name for p in OUT.glob("*.wav")))
