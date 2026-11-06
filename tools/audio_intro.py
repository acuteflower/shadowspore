#!/usr/bin/env python3
"""Synthesized placeholders for the intro (numpy + stdlib wave, no recordings): knocks on the iron lid from below, the lid
grinding aside, a gasp and a cough, her weight hitting the stones. Re-run to replace the WAV files in assets/audio/intro/
deterministically."""
from pathlib import Path
import wave

import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "intro"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = np.random.default_rng(11)


def tt(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def band(x, lo, hi):
    """A crude band-pass by FFT."""
    spec = np.fft.rfft(x)
    freq = np.fft.rfftfreq(len(x), 1.0 / RATE)
    spec *= ((freq >= lo) & (freq <= hi)).astype(float)
    return np.fft.irfft(spec, len(x))


def save(name, signal, level=0.7):
    signal = signal / (np.max(np.abs(signal)) + 1e-9) * level
    pcm = np.int16(np.clip(signal, -1, 1) * 32767)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm.tobytes())


# two knocks on iron: inharmonic partials that ring and die, a little click
t = tt(0.7)
partials = [(96, 1.0, 9), (147, 0.7, 12), (231, 0.5, 15), (352, 0.35, 20), (571, 0.2, 26)]
knock = sum(a * np.sin(2 * np.pi * f * t + 0.3 * i) * np.exp(-t * d) for i, (f, a, d) in enumerate(partials))
knock += 0.6 * band(rng.normal(0, 1, len(t)), 800, 4000) * np.exp(-t * 90)
save("knock", knock)

# the lid grinding over stone: gritty noise that stutters, with a groaning resonance that slides
t = tt(1.4)
grit = band(rng.normal(0, 1, len(t)), 200, 1800)
stutter = 0.55 + 0.45 * np.sin(2 * np.pi * (5.0 + 2.0 * t) * t) ** 2
groan = np.sin(2 * np.pi * np.cumsum(290 - 70 * t / t[-1] + 8 * np.sin(t * 40)) / RATE)
env = np.minimum(1, t * 6) * np.minimum(1, (t[-1] - t) * 4)
scrape = (grit * 0.9 * stutter + 0.35 * groan * stutter + 0.25 * band(rng.normal(0, 1, len(t)), 2500, 6000) * stutter ** 2) * env
save("lid_scrape", scrape)

# a heavy body hitting stone: low thump and cloth
t = tt(0.5)
thud = np.sin(2 * np.pi * (78 - 30 * t) * t) * np.exp(-t * 14) + 0.5 * band(rng.normal(0, 1, len(t)), 100, 900) * np.exp(-t * 18)
save("body_thud", thud, 0.8)

# a gasp: an inhale that tears open, then a shaky exhale
t = tt(1.5)
inhale = band(rng.normal(0, 1, len(t)), 500, 3200) * np.clip(np.sin(np.pi * np.clip(t / 0.55, 0, 1)) ** 1.5, 0, 1) * (t < 0.55)
rasp = np.sin(2 * np.pi * np.cumsum(180 + 40 * np.sin(t * 9)) / RATE) * (t > 0.6) * np.exp(-(t - 0.6) * 3) * 0.25
exhale = band(rng.normal(0, 1, len(t)), 300, 2200) * (t > 0.6) * np.exp(-(t - 0.6) * 3.2) * (0.7 + 0.3 * np.sin(2 * np.pi * 7 * t))
save("gasp", inhale + exhale * 0.6 + rasp, 0.65)

# a cough, twice: a burst of breath with a low voice in it
t = tt(0.9)
sig = np.zeros_like(t)
for start, length, level in ((0.05, 0.16, 1.0), (0.38, 0.13, 0.75)):
    n = (t >= start) & (t < start + length)
    local = (t - start)[n]
    env = np.minimum(1, local * 90) * np.exp(-local * 14)
    voice = np.sin(2 * np.pi * np.cumsum(150 + 60 * np.exp(-local * 20)) / RATE)[: len(local)] if len(local) else local
    noise = band(rng.normal(0, 1, len(t)), 400, 2600)[n]
    sig[n] += level * env * (0.8 * noise + 0.5 * voice)
save("cough", sig, 0.7)
# a heartbeat, lub-dub (loops every beat of the wounded state)
t = tt(0.6)
beat = np.zeros_like(t)
for start, level in ((0.0, 1.0), (0.28, 0.7)):
    local = np.clip(t - start, 0, None)
    beat += level * (t >= start) * np.sin(2 * np.pi * (62 - 20 * local) * local) * np.exp(-local * 22)
save("heartbeat", beat, 0.8)
# a soft tick for typed dialogue letters
t = tt(0.05)
save("tick", np.sin(2 * np.pi * 620 * t) * np.exp(-t * 90) + 0.4 * band(rng.normal(0, 1, len(t)), 1500, 5000) * np.exp(-t * 140), 0.5)
print("wrote the intro sounds")
