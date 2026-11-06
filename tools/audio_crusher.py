#!/usr/bin/env python3
"""Reproducible heavy creature cues for the Void Crusher: tectonic sub-bass, grinding basalt, dry impacts and hollow bursts.
Synthetic placeholders (numpy only), normalised below full scale; same format as audio_listener.py."""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parent.parent / 'assets/audio'
RATE = 22050
rng = np.random.default_rng(777)


def lowpass(x, n):
    return np.convolve(x, np.ones(n) / n, mode='same')


def grind(t, depth=1.0):
    """Basalt blocks scraping: low-passed noise chopped by a ragged stick-slip envelope."""
    noise = lowpass(rng.uniform(-1, 1, len(t)), 9)
    slip = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * (23 * t + 4 * np.sin(2 * np.pi * 3.1 * t)))) * np.abs(np.sin(2 * np.pi * 37 * t)) ** .5
    return noise * slip * depth


def thud(t, f0=58, decay=9):
    return np.sin(2 * np.pi * (f0 * t - 18 * t * t)) * np.exp(-t * decay)


def crack(t, decay=30):
    return lowpass(rng.uniform(-1, 1, len(t)), 3) * np.exp(-t * decay)


def make(kind, seconds):
    t = np.arange(int(RATE * seconds)) / RATE
    p = t / seconds
    if kind == 'notice':      # a low rising growl
        phase = 2 * np.pi * (36 * t + 16 * t * t)
        s = (np.sin(phase) + .35 * np.sin(phase * 2.01) + grind(t, .5)) * np.sin(np.pi * p) ** .8
    elif kind == 'charge':    # stone grinding up while the arm rises
        phase = 2 * np.pi * (40 * t + 30 * t * t)
        s = (np.sin(phase) + .4 * np.sin(phase * 2.03) + grind(t, 1.1)) * p ** 1.3 * (1 + .12 * np.sin(2 * np.pi * 13 * t))
    elif kind == 'slam':      # the fall (whoosh), then the impact at 0.12 s with splitting stone
        hit = np.maximum(t - .12, 0)
        whoosh = lowpass(rng.uniform(-1, 1, len(t)), 15) * np.clip(t / .12, 0, 1) ** 2 * (t < .12) * .5
        s = whoosh + (thud(hit, 52, 7) * 1.6 + crack(hit, 22) * 1.2 + grind(hit, .5) * np.exp(-hit * 6)) * (t >= .12)
    elif kind == 'rush':      # an avalanche over cobbles
        rumble = lowpass(rng.uniform(-1, 1, len(t)), 21) * 1.3
        pounding = np.sin(2 * np.pi * 46 * t) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 7.5 * t)))
        s = (rumble + pounding + grind(t, .6)) * np.minimum(p * 6, 1) * np.minimum((1 - p) * 4, 1)
    elif kind == 'sweep':     # a heavy swing and a stony slap
        whoosh = lowpass(rng.uniform(-1, 1, len(t)), 13) * np.sin(np.pi * np.clip(p * 1.6, 0, 1)) ** 2
        late = np.maximum(t - .1, 0)
        s = whoosh * .9 + (thud(late, 70, 14) * .9 + crack(late, 40) * .8) * (t >= .1)
    elif kind == 'core_hit':  # a bright, wet strike on the exposed core and a dropping moan
        phase = 2 * np.pi * (240 * t - 190 * t * t)
        s = (np.sin(phase) * np.exp(-t * 7) + crack(t, 16) * .7 + thud(t, 80, 10) * .6)
    elif kind == 'front_hit': # steel on horn: a dry clack and a tiny ring
        ring = np.sin(2 * np.pi * 1180 * t) * np.exp(-t * 38) * .5 + np.sin(2 * np.pi * 1930 * t) * np.exp(-t * 55) * .3
        s = ring + crack(t, 70) * 1.1
    elif kind == 'stun':      # the rock-hard collision, a clunk and a long dizzy groan
        late = np.maximum(t - .02, 0)
        phase = 2 * np.pi * (44 * t - 6 * t * t)
        s = thud(late, 48, 6) * 1.8 + crack(late, 18) * 1.1 + np.sin(phase) * np.exp(-t * 2.2) * .5 * np.clip(t * 4, 0, 1)
    elif kind == 'death':     # a hollow bursting of slabs, then a hissing liquefaction
        burst = thud(t, 44, 5) * 1.5 + crack(t, 12) * 1.2 + grind(t, .6) * np.exp(-t * 3)
        hiss = lowpass(rng.uniform(-1, 1, len(t)), 3) * np.clip((t - .5) * 3, 0, 1) * np.exp(-(t - .5).clip(0) * 2.6) * .35
        s = burst + hiss
    elif kind == 'step':      # one heavy footfall with a scatter of gravel
        s = thud(t, 62, 18) * 1.4 + crack(t, 45) * .6 + lowpass(rng.uniform(-1, 1, len(t)), 5) * np.exp(-t * 14) * .25
    else:
        raise ValueError(kind)
    s = np.tanh(s * 1.25)
    s *= .5 / max(float(np.abs(s).max()), 1e-9)
    s *= np.minimum((1 - p) * 40, 1) * np.minimum(t * 600, 1)
    with wave.open(str(ROOT / f'crusher_{kind}.wav'), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((s * 32767).astype('<i2').tobytes())


for kind, seconds in [('notice', .9), ('charge', .95), ('slam', .9), ('rush', .55), ('sweep', .5), ('core_hit', .45), ('front_hit', .22), ('stun', 1.2), ('death', 1.5), ('step', .3)]:
    make(kind, seconds)
print('Crusher: ten spatial creature cues')
