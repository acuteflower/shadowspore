#!/usr/bin/env python3
"""Lichtfischer cues (docs/enemies/lichtfischer.md): glass, cold water and a lamp that hums a little too sweetly.
Ten synthetic placeholders written to assets/audio/fisher_*.wav, normalised below full scale; numpy only, deterministic.
"""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parent.parent / 'assets/audio'
RATE = 22050
rng = np.random.default_rng(2611)


def lowpass(x, k):
    return np.convolve(x, np.ones(k) / k, mode='same')


def bandnoise(n, lo, hi):
    """Noise between two moving-average widths: a cheap band."""
    x = rng.uniform(-1., 1., n)
    return lowpass(x, lo) - lowpass(x, hi)


def chime(t, f, decay, partials=(1.0, 2.76, 5.4), gains=(1.0, .5, .25)):
    """A glass-like bell: inharmonic partials with their own decay."""
    out = np.zeros_like(t)
    for p, g in zip(partials, gains):
        out += g * np.sin(2 * np.pi * f * p * t) * np.exp(-t * decay * (1 + .4 * p))
    return out


def splash(n, power=1.0):
    t = np.arange(n) / RATE
    body = bandnoise(n, 3, 40) * np.exp(-t * 14) * power
    drops = np.zeros(n)
    for k in range(int(6 * power) + 2):
        at = int(rng.uniform(.02, .35) * RATE)
        if at < n - 400:
            tt = np.arange(n - at) / RATE
            f = rng.uniform(900, 2200)
            drops[at:] += .12 * np.sin(2 * np.pi * (f + 2400 * tt) * tt) * np.exp(-tt * 55)
    return body + drops


def finish(signal, peak=.5, fade=40):
    signal = np.tanh(signal * 1.2)
    signal *= peak / max(float(np.abs(signal).max()), 1e-9)
    p = np.linspace(0, 1, len(signal))
    signal *= np.minimum((1 - p) * fade, 1)
    return signal


def write(name, signal):
    with wave.open(str(ROOT / f'fisher_{name}.wav'), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((signal * 32767).astype('<i2').tobytes())


def cue(name, seconds):
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    p = t / seconds
    if name == 'twitch':  # the lantern tugs: two small glass ticks over a faint hum
        s = chime(t, 1560, 20) * .5 + chime(np.maximum(t - .11, 0), 1860, 24) * (t > .11) * .45
        s += .12 * np.sin(2 * np.pi * 311 * t) * np.sin(np.pi * p) ** 2
        return finish(s, .34)
    if name == 'windup':  # the bait dips: the hum falls, water draws in
        f = 540 - 300 * p
        s = .5 * np.sin(2 * np.pi * np.cumsum(f) / RATE) * (1 - p * .6) + bandnoise(n, 5, 60) * .35 * p ** 1.5
        s += .25 * chime(t, 880, 6) * (1 - p)
        return finish(s, .42)
    if name == 'snap':  # glass teeth clamp, water bursts
        hit = np.maximum(t - .06, 0)
        clack = bandnoise(n, 2, 9) * np.exp(-hit * 90) * (t > .06) * 1.6
        teeth = sum(chime(np.maximum(t - .06 - k * .012, 0), 2100 + k * 340, 40) * (t > .06 + k * .012) for k in range(5)) * .22
        s = splash(n, 1.4) * .9 + clack + teeth
        s += .55 * np.sin(2 * np.pi * (96 - 40 * np.minimum(hit * 4, 1)) * t) * np.exp(-hit * 12) * (t > .06)
        return finish(s, .6)
    if name == 'swell':  # the light swells: a rising, too-sweet tone, beating against itself
        f = 392 + 520 * p ** 1.6
        ph = 2 * np.pi * np.cumsum(f) / RATE
        s = (np.sin(ph) + np.sin(ph * 1.012) * .8 + .3 * np.sin(ph * 2.0)) * p ** 1.2 * .5
        s += bandnoise(n, 2, 14) * .12 * p
        return finish(s, .46, 20)
    if name == 'flash':  # the burst: a white crack, glassy shimmer, the hum collapses
        hit = np.maximum(t - .02, 0)
        crack = bandnoise(n, 2, 7) * np.exp(-hit * 38) * (t > .02) * 1.4
        shimmer = sum(chime(t, 1200 + k * 690, 9) * .22 for k in range(6))
        fall = .5 * np.sin(2 * np.pi * np.cumsum(900 * np.exp(-p * 4) + 90) / RATE) * np.exp(-p * 3)
        return finish(crack + shimmer * np.exp(-p * 2) + fall, .62)
    if name == 'orb':  # three lights cast: soft rising blips, staggered
        s = np.zeros(n)
        for k in range(3):
            at = k * .24
            tt = np.maximum(t - at, 0)
            f = 700 + 180 * k + 600 * tt
            s += (t > at) * .4 * np.sin(2 * np.pi * np.cumsum(f * (t > at)) / RATE) * np.exp(-tt * 9)
        s += bandnoise(n, 4, 40) * .1
        return finish(s, .4)
    if name == 'burst':  # one false lamp pops on the water
        s = chime(t, 1320, 14) * .55 + bandnoise(n, 3, 24) * np.exp(-t * 28) * .7
        s += .35 * np.sin(2 * np.pi * (240 - 120 * p) * t) * np.exp(-t * 18)
        return finish(s, .46)
    if name == 'dive':  # it sinks away: a gulp, bubbles, the hum sliding down
        gulp = bandnoise(n, 6, 80) * np.sin(np.pi * np.minimum(p * 3, 1)) * np.exp(-p * 3)
        bubbles = np.zeros(n)
        for k in range(9):
            at = int(rng.uniform(.1, .8) * n)
            tt = np.arange(n - at) / RATE
            f = rng.uniform(300, 700)
            bubbles[at:] += .25 * np.sin(2 * np.pi * (f + 1800 * tt) * tt) * np.exp(-tt * 45)
        slide = .3 * np.sin(2 * np.pi * np.cumsum(260 - 200 * p) / RATE) * (1 - p)
        return finish(gulp * .8 + bubbles + slide + splash(n, .8) * .5, .5)
    if name == 'hurt':  # a cracked chime and a wet grunt
        s = chime(t, 1080, 18) * .6 + bandnoise(n, 4, 50) * np.exp(-t * 14) * .8
        s += .5 * np.sin(2 * np.pi * (150 - 70 * p) * t) * np.exp(-t * 8)
        return finish(s, .5)
    if name == 'death':  # the lantern goes out: a long sinking hum, glass falling apart, water settling
        slide = np.sin(2 * np.pi * np.cumsum(420 * np.exp(-p * 3.2) + 38) / RATE) * np.exp(-p * 1.6)
        glass = sum(chime(np.maximum(t - rng.uniform(0, .5), 0), rng.uniform(1100, 2400), 12) * .12 for k in range(7))
        s = slide * .7 + glass + splash(n, 1.0) * .5 + bandnoise(n, 8, 90) * (1 - p) * .25
        return finish(s, .52, 12)
    raise ValueError(name)


for name, seconds in [('twitch', .42), ('windup', .75), ('snap', .6), ('swell', .85), ('flash', .9),
                      ('orb', .8), ('burst', .45), ('dive', .8), ('hurt', .4), ('death', 1.5)]:
    write(name, cue(name, seconds))
print('Fisher: ten cues')
