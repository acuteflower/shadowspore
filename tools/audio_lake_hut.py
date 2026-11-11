#!/usr/bin/env python3
"""Synthesized placeholders for the lake witch's house (docs/seehexe_konzept.md 9; numpy + stdlib wave), deterministic:
    chimes.wav       crystal wind chimes under the eave, a seamless 16 s loop of sparse glassy notes (four pitches, random order, soft ring-out)
    lake_lap.wav     water lapping at the jetty's posts and the stilts, a seamless 12 s loop
    ward_wake.wav    a ward stone wakes: a rising glassy tone with a breath of light (step 3 lets the ring wake stone by stone)
    ward_ring.wav    the ring closes: a soft chord of the four chime notes, the void hissing back
Writes assets/audio/lake_hut/*.wav.   py -3 tools/audio_lake_hut.py"""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "lake_hut"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = np.random.default_rng(73)
NOTES = (1318.5, 1567.98, 1760.0, 2093.0)  # E6 G6 A6 C7: glassy, pentatonic, never a dissonance


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


def glass(freq, length, decay=1.4, bright=0.35):
    """A struck crystal: a sine with two inharmonic partials, a click of a strike and a long soft ring-out."""
    t = tt(length)
    env = np.exp(-t * decay) * np.minimum(1.0, t / 0.004)
    tone = np.sin(2 * np.pi * freq * t) + bright * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t * 4) + 0.18 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t * 9)
    return tone * env * (1.0 + 0.04 * np.sin(2 * np.pi * 5.5 * t))


def loop_place(total, sig, at):
    """Adds `sig` at sample `at`, wrapping round the end (a seamless loop)."""
    n = len(sig)
    idx = (np.arange(n) + at) % len(total)
    np.add.at(total, idx, sig)


# chimes: clusters of 1-4 strikes (a gust moves the strings), quiet gaps between
length = 16.0
chimes = np.zeros(int(RATE * length))
t0 = 0.4
while t0 < length:
    for k in range(int(rng.integers(1, 5))):
        note = NOTES[int(rng.integers(0, 4))] * (1.0 + rng.uniform(-0.004, 0.004))
        loop_place(chimes, glass(note, 3.2, decay=rng.uniform(1.1, 1.8)) * rng.uniform(0.35, 1.0), int((t0 + k * rng.uniform(0.09, 0.28)) * RATE))
    t0 += rng.uniform(1.6, 4.2)
save("chimes", chimes, 0.5)

# lake_lap: soft wavelets slapping wood, a low wash under them
length = 12.0
lap = band(rng.normal(0, 1, int(RATE * length)), 80, 500) * 0.25
t = tt(length)
lap *= 0.6 + 0.4 * np.sin(2 * np.pi * t / length * 3) ** 2
s = 0.3
while s < length:
    n = int(RATE * 0.35)
    burst = band(rng.normal(0, 1, n), 300, 2400) * np.exp(-tt(0.35) * 14) * rng.uniform(0.4, 1.0)
    slap = np.sin(2 * np.pi * rng.uniform(140, 220) * tt(0.35)) * np.exp(-tt(0.35) * 22) * 0.6
    loop_place(lap, burst + slap, int(s * RATE))
    s += rng.uniform(0.7, 1.9)
save("lake_lap", lap, 0.45)

# ward_wake: a rising glassy swell, then the strike
t = tt(1.6)
f = 600 + 900 * (t / t[-1]) ** 1.5
swell = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.sin(np.pi * np.clip(t / 1.2, 0, 1)) ** 2 * 0.5
air = band(rng.normal(0, 1, len(t)), 2000, 7000) * np.sin(np.pi * t / t[-1]) * 0.12
wake = swell + air
strike = glass(NOTES[2], 1.6, decay=2.0)
wake[int(RATE * 1.1):] += strike[: len(wake) - int(RATE * 1.1)]
save("ward_wake", wake, 0.6)

# ward_ring: the four notes as a chord, and the void's hiss falling away
t = tt(3.6)
chord = sum(glass(n, 3.6, decay=0.9, bright=0.25) * (1.0 - 0.15 * i) for i, n in enumerate(NOTES))
hiss = band(rng.normal(0, 1, len(t)), 3000, 9000) * np.exp(-t * 2.2) * 0.35
low = np.sin(2 * np.pi * 55 * t) * np.exp(-t * 1.5) * 0.4
save("ward_ring", chord + hiss + low, 0.7)
print("wrote", sorted(p.name for p in OUT.glob("*.wav")))
