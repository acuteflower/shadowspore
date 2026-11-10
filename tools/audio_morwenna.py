#!/usr/bin/env python3
"""Placeholder sounds of Morwenna's fight (docs/enemies/boss_mora.md): synthetic, reproducible (numpy only), 22.05 kHz mono 16 bit, normalised below
full scale; the same format as audio_crusher.py. Her voice is always doubled (the dossier's Zweistimmigkeit): a high witch's tone over a scratching,
lower void echo a moment late. Cues = the keys of `boss_morwenna.audio` in data/enemies.json.
    py -3 tools/audio_morwenna.py        -> assets/audio/morwenna/<cue>.wav, then `Godot --headless --import`"""
from pathlib import Path
import wave
import numpy as np

OUT = Path(__file__).resolve().parent.parent / 'assets/audio/morwenna'
RATE = 22050
rng = np.random.default_rng(4471)


def lowpass(x, n):
    return np.convolve(x, np.ones(n) / n, mode='same')


def noise(n, smooth=1):
    x = rng.uniform(-1, 1, n)
    return lowpass(x, smooth) if smooth > 1 else x


def env(t, attack, decay):
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-np.maximum(t - attack, 0) * decay)


def late(t, at):
    return np.maximum(t - at, 0), (t >= at)


def voice(t, f0, glide, rough, seconds):
    """The doubled voice: a witch's wail with vibrato, and the void under it (a fifth and an octave down, ring-modulated, 40 ms late, crackling)."""
    p = t / seconds
    vib = 1 + 0.025 * np.sin(2 * np.pi * 5.5 * t)
    f = f0 * (1 + glide * p) * vib
    phase = 2 * np.pi * np.cumsum(f) / RATE
    high = np.sin(phase) + 0.4 * np.sin(2 * phase) + 0.2 * np.sin(3 * phase)
    d = int(0.04 * RATE)
    low_f = f * 0.5 * (1 + 0.02 * np.sin(2 * np.pi * 31 * t))
    low_phase = 2 * np.pi * np.cumsum(low_f) / RATE
    low = (np.sign(np.sin(low_phase)) * 0.5 + np.sin(low_phase * 1.5)) * np.sin(2 * np.pi * 71 * t)
    low = np.concatenate([np.zeros(d), low[:-d]]) if d < len(low) else low
    crackle = noise(len(t)) * (rng.uniform(0, 1, len(t)) < 0.03) * rough
    shape = np.sin(np.pi * np.clip(p, 0, 1)) ** 0.6
    return (high * 0.6 + low * 0.45 * rough + crackle) * shape


def glass(t, freqs, decay):
    return sum(np.sin(2 * np.pi * f * t) * np.exp(-t * decay * (1 + i * 0.4)) for i, f in enumerate(freqs))


def whoosh(t, seconds, bright=7):
    p = t / seconds
    return noise(len(t), bright) * np.sin(np.pi * np.clip(p, 0, 1)) ** 2


def thud(t, f0=60, decay=10):
    return np.sin(2 * np.pi * (f0 * t - 16 * t * t)) * np.exp(-t * decay)


def stutter(t, seconds):
    """A held frame: a short buzz chopped into crackling slices."""
    gate = (np.sin(2 * np.pi * 38 * t) > 0.2).astype(float)
    return (np.sign(np.sin(2 * np.pi * 120 * t)) * 0.4 + noise(len(t), 2)) * gate * np.exp(-t * 6)


def make(kind, seconds):
    t = np.arange(int(RATE * seconds)) / RATE
    p = t / seconds
    if kind == 'scream':
        s = voice(t, 520, 0.35, 1.0, seconds) + whoosh(t, seconds, 5) * 0.3
    elif kind == 'crack':      # the mirror mask splits
        s = glass(t, [1870, 2630, 3410, 4720], 9) * 0.6 + noise(len(t), 2) * np.exp(-t * 30)
    elif kind == 'land':       # she hits the clay head first
        s = thud(t, 54, 8) * 1.5 + noise(len(t), 13) * np.exp(-t * 14) * 0.8
    elif kind == 'stutter':
        s = stutter(t, seconds)
    elif kind == 'whet':       # sickles whetted against each other
        h, on = late(t, 0.18)
        s = (glass(t, [2400, 3300], 18) + noise(len(t), 3) * np.exp(-t * 9) * 0.6) + (glass(h, [2600, 3550], 14) + noise(len(t), 3) * np.exp(-h * 8) * 0.6) * on
    elif kind == 'slash':
        s = whoosh(t, seconds, 4) * 0.9 + glass(t, [3100], 40) * 0.25
    elif kind == 'scissor':    # two blades shutting: a ringing double clack
        h, on = late(t, 0.05)
        s = whoosh(t, seconds, 5) * 0.5 + glass(t, [2900, 4100], 22) * 0.6 + glass(h, [3200, 4400], 20) * 0.6 * on
    elif kind == 'dash':
        s = whoosh(t, seconds, 3) * (0.6 + 0.4 * p)
    elif kind == 'cast':       # a breath drawn in and a green hum rising
        phase = 2 * np.pi * (180 * t + 220 * t * t)
        s = np.sin(phase) * 0.5 * p + noise(len(t), 9) * np.sin(np.pi * p) * 0.4 + voice(t, 300, 0.2, 0.5, seconds) * 0.25
    elif kind == 'root':       # roots tearing out of the ground
        s = noise(len(t), 6) * env(t, 0.01, 10) * 1.1 + thud(t, 90, 16) * 0.8 + (np.sin(2 * np.pi * 34 * t) > 0.6) * noise(len(t), 2) * 0.2 * np.exp(-t * 7)
    elif kind == 'sap':        # wet drops thrown
        s = sum(np.sin(2 * np.pi * (380 + 90 * k) * np.maximum(t - 0.05 * k, 0)) * np.exp(-np.maximum(t - 0.05 * k, 0) * 26) * (t >= 0.05 * k) for k in range(5)) * 0.5 + whoosh(t, seconds, 8) * 0.3
    elif kind == 'vanish':     # sucked into smoke
        s = noise(len(t), 4) * (1 - p) ** 2 * 0.8 + np.sin(2 * np.pi * (900 - 700 * p) * t) * 0.25 * (1 - p)
    elif kind == 'poof':       # a clone crumbles into mist
        s = noise(len(t), 3) * env(t, 0.01, 9) * 0.7 + glass(t, [1500, 2250], 25) * 0.3
    elif kind == 'swap':       # a glitch: two short buzzes, swapped
        s = stutter(t, seconds) * 0.8 + glass(t, [880, 1320], 12) * 0.4 * np.sign(np.sin(2 * np.pi * 9 * t))
    elif kind == 'mirror':     # the mask turns, shards charge
        s = glass(t, [1240, 1860, 2790], 3) * np.sin(np.pi * p) * 0.6 + noise(len(t), 2) * 0.05
    elif kind == 'shard':
        s = glass(t, [3500, 5200], 30) * 0.6 + whoosh(t, seconds, 2) * 0.4
    elif kind == 'burrow':     # into the roots
        s = noise(len(t), 15) * np.sin(np.pi * p) * 1.0 + thud(t, 45, 4) * 0.5
    elif kind == 'erupt':
        s = thud(t, 50, 6) * 1.4 + noise(len(t), 5) * env(t, 0.005, 8) * 1.0 + glass(t, [700], 12) * 0.2
    elif kind == 'cage':       # splinters rammed into slate
        s = sum(glass(np.maximum(t - 0.07 * k, 0), [2200 + 300 * k], 30) * (t >= 0.07 * k) for k in range(4)) * 0.5 + thud(t, 80, 14) * 0.4
    elif kind == 'threads':    # burning threads spanned
        s = (np.sin(2 * np.pi * 660 * t) + np.sin(2 * np.pi * 663 * t) + 0.5 * np.sin(2 * np.pi * 990 * t)) * 0.3 * np.minimum(p * 6, 1) * (1 - p) ** 0.5 + noise(len(t), 2) * 0.08
    elif kind == 'burst':      # the pincer's crossing explodes
        s = thud(t, 48, 5) * 1.2 + noise(len(t), 4) * env(t, 0.003, 7) * 1.1
    elif kind == 'whirl':      # the carousel spins up
        s = whoosh(t, seconds, 6) * (0.5 + 0.5 * np.sin(2 * np.pi * (3 + 9 * p) * t)) + voice(t, 420, 0.1, 0.6, seconds) * 0.25
    elif kind == 'leech':      # she drinks from the tree: a deep sucking drone
        phase = 2 * np.pi * (70 * t)
        s = (np.sin(phase) + 0.5 * np.sin(phase * 1.5)) * (0.6 + 0.4 * np.sin(2 * np.pi * 1.4 * t)) * np.minimum(p * 4, 1) * np.minimum((1 - p) * 4, 1) + noise(len(t), 30) * 0.4
    elif kind == 'pulse':      # a ring of life force runs over the hollow
        s = thud(t, 70, 5) * 1.0 + glass(t, [440, 660], 6) * 0.3
    elif kind == 'seam':       # a curse seam bursts
        s = noise(len(t), 2) * env(t, 0.002, 18) * 0.9 + glass(t, [1100, 1650], 20) * 0.3
    elif kind == 'charge':     # the split's beams charge
        f = 300 + 900 * p ** 1.5
        s = np.sin(2 * np.pi * np.cumsum(f) / RATE) * 0.5 * p + noise(len(t), 3) * 0.2 * p
    elif kind == 'beam':
        s = (np.sign(np.sin(2 * np.pi * 140 * t)) * 0.3 + noise(len(t), 2) * 0.6) * env(t, 0.005, 3) + thud(t, 60, 9) * 0.7
    elif kind == 'dive':       # a raven dives
        s = whoosh(t, seconds, 4) * 0.8 + np.sin(2 * np.pi * (1600 - 900 * p) * t) * 0.15 * np.sin(np.pi * p)
    elif kind == 'stagger':    # struck out of the act: a choked double cry
        s = voice(t, 380, -0.3, 1.2, seconds) * 0.9 + stutter(t, seconds) * 0.4
    elif kind == 'shatter':    # the phase turns: the mirror bursts
        s = glass(t, [1500, 2240, 3100, 4300, 5600], 5) * 0.6 + noise(len(t), 2) * env(t, 0.002, 6) * 0.9 + thud(t, 50, 6) * 0.8
    elif kind == 'death':      # the last cry, the void echo falling away
        s = voice(t, 460, -0.45, 1.3, seconds) * np.exp(-t * 0.6)
    elif kind == 'release':    # golden dust: a soft rising chime, no void left in it
        s = sum(np.sin(2 * np.pi * f * t) * np.exp(-np.maximum(t - d, 0) * 1.6) * (t >= d) for f, d in ((523, 0.0), (659, 0.25), (784, 0.5), (1046, 0.8))) * 0.35 * (1 - p) ** 0.3
    else:
        raise ValueError(kind)
    s = np.nan_to_num(s)
    fade = min(len(s) // 20, 400)
    if fade:
        s[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(s)) or 1.0
    return s / peak * 0.82


CUES = {'scream': 1.3, 'crack': 0.7, 'land': 0.8, 'stutter': 0.35, 'whet': 0.55, 'slash': 0.28, 'scissor': 0.45, 'dash': 0.3, 'cast': 0.6,
        'root': 0.5, 'sap': 0.45, 'vanish': 0.45, 'poof': 0.5, 'swap': 0.45, 'mirror': 0.6, 'shard': 0.3, 'burrow': 0.8, 'erupt': 0.8,
        'cage': 0.6, 'threads': 1.2, 'burst': 0.8, 'whirl': 1.2, 'leech': 2.2, 'pulse': 0.9, 'seam': 0.5, 'charge': 1.2, 'beam': 0.9,
        'dive': 0.6, 'stagger': 0.8, 'shatter': 1.4, 'death': 2.2, 'release': 2.6}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for kind, seconds in CUES.items():
        data = (make(kind, seconds) * 32767).astype(np.int16)
        with wave.open(str(OUT / (kind + '.wav')), 'wb') as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes(data.tobytes())
    print('wrote %d cues to %s' % (len(CUES), OUT))


if __name__ == '__main__':
    main()
