#!/usr/bin/env python3
"""Reproducible placeholder cues for Mornath, the Sky Cleaver: leathery blade-edged wing whooshes with a faint metallic shimmer,
a tense takeoff creak, a heavy landing, viscous void beads, a crash with shards, a drawn breath and a dull chitin hit.
Synthetic (numpy only), normalised below full scale, same format and conventions as audio_crusher.py."""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parent.parent / 'assets/audio'
RATE = 22050
rng = np.random.default_rng(31337)


def lowpass(x, n):
    return np.convolve(x, np.ones(n) / n, mode='same')


def bandpass(x, lo, hi):
    return lowpass(x, lo) - lowpass(x, hi)


def noise(t):
    return rng.uniform(-1, 1, len(t))


def shimmer(t, base=2400.0, depth=0.5):
    """Thin metallic overtones, like blades brushing each other."""
    s = np.zeros(len(t))
    for k, f in enumerate([1.0, 1.51, 2.27, 3.1]):
        s += np.sin(2 * np.pi * base * f * t + k * 1.7 + 3 * np.sin(2 * np.pi * (7 + 3 * k) * t)) / (1 + k)
    return s * depth


def thud(t, f0=64, decay=11):
    return np.sin(2 * np.pi * (f0 * t - 20 * t * t)) * np.exp(-t * decay)


def crack(t, decay=34):
    return lowpass(noise(t), 3) * np.exp(-t * decay)


def whoosh(t, peak, width, rough=15):
    """Air through blades: band-limited noise swelling to `peak` seconds, flutter from the individual lamellae."""
    env = np.exp(-((t - peak) / width) ** 2)
    air = lowpass(noise(t), rough)
    flutter = 0.65 + 0.35 * np.sign(np.sin(2 * np.pi * 61 * t + 4 * np.sin(2 * np.pi * 5 * t))) * np.abs(np.sin(2 * np.pi * 29 * t)) ** .5
    return air * env * flutter


def make(name, seconds):
    t = np.arange(int(RATE * seconds)) / RATE
    p = t / seconds
    if name == 'wing_soft':
        s = whoosh(t, .16, .085, 19) * 1.0 + shimmer(t, 2100, .06) * np.exp(-((t - .16) / .08) ** 2) + thud(t, 52, 16) * .18 * np.exp(-((t - .1) / .12) ** 2)
    elif name == 'wing_strong':
        s = whoosh(t, .17, .1, 13) * 1.15 + shimmer(t, 2600, .22) * np.exp(-((t - .19) / .09) ** 2) \
            + (bandpass(noise(t), 3, 25) * np.exp(-((t - .12) / .05) ** 2)) * .8 + thud(np.maximum(t - .12, 0), 48, 13) * .45 * (t >= .12)
    elif name == 'takeoff':      # a creaking, shivering tension that rises into a burst of blades at 0.5 s
        wind = np.clip(p / .83, 0, 1)
        creak = np.sin(2 * np.pi * (95 + 130 * wind * wind) * t + 5 * np.sin(2 * np.pi * (9 + 18 * wind) * t)) * 0.5
        shiver = shimmer(t, 1800 + 900 * wind, .15) * wind ** 2
        rustle = lowpass(noise(t), 9) * (0.1 + 0.5 * wind) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 34 * t)))
        late = np.maximum(t - .5, 0)
        burst = (whoosh(t, .58, .06, 11) * 1.6 + crack(late, 20) * .5 + thud(late, 50, 10) * .6) * (t >= .48)
        s = (creak + shiver + rustle) * (t < .52) * np.minimum(1, (0.52 - t) * 30) + burst
    elif name == 'land':         # a heavy soft thump and the blades folding over each other
        late = np.maximum(t - .04, 0)
        s = thud(late, 56, 9) * 1.5 * (t >= .04) + lowpass(noise(t), 7) * np.exp(-t * 7) * .3 \
            + shimmer(t, 1700, .12) * np.exp(-((t - .22) / .12) ** 2) + lowpass(noise(t), 4) * np.exp(-((t - .28) / .1) ** 2) * .25
    elif name == 'bead':         # viscous: a stretching tick, then a thick wet plop that sinks in pitch
        tick = np.sin(2 * np.pi * 900 * t) * np.exp(-t * 90) * .12 * (t < .07)
        late = np.maximum(t - .06, 0)
        plop = np.sin(2 * np.pi * (240 * late - 520 * late * late)) * np.exp(-late * 20) * (t >= .06)
        gloop = lowpass(noise(t), 11) * np.exp(-late * 28) * .35 * (t >= .06)
        s = tick + plop * 1.1 + gloop + np.sin(2 * np.pi * (130 - 60 * late) * t) * np.exp(-late * 12) * .3 * (t >= .06)
    elif name == 'crash':        # heavy body, wing blades snapping, shards skittering away
        s = thud(t, 46, 6) * 1.7 + crack(t, 16) * 1.0 + lowpass(noise(t), 6) * np.exp(-t * 9) * .5
        for k in range(14):
            at = .16 + k * .043 + rng.uniform(0, .03)
            if at < seconds - .05:
                tt = np.maximum(t - at, 0)
                s += np.sin(2 * np.pi * rng.uniform(1500, 3800) * tt) * np.exp(-tt * rng.uniform(60, 130)) * (t >= at) * rng.uniform(.06, .2)
    elif name == 'breath':       # very quiet: a drawn raspy breath in and a long, low out
        inhale = np.exp(-((t - .5) / .3) ** 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 70 * t))
        exhale = np.exp(-((t - 1.2) / .38) ** 2)
        rasp = bandpass(noise(t), 3, 22) * (inhale * .7 + exhale)
        drone = np.sin(2 * np.pi * 46 * t) * exhale * .35 + np.sin(2 * np.pi * 91 * t) * exhale * .1
        s = rasp + drone
    elif name == 'hit':          # dull chitin: a short thump with a muffled clack
        s = thud(t, 85, 24) * .9 + crack(t, 60) * 1.0 + np.sin(2 * np.pi * 640 * t) * np.exp(-t * 55) * .22 + shimmer(t, 2100, .05) * np.exp(-t * 40)
    elif name == 'charge':       # feathers charging: a rising shimmer of thin blades over a low, tightening hum
        rise = np.clip(p, 0, 1) ** 1.6
        hum = np.sin(2 * np.pi * (70 + 110 * rise) * t + 3 * np.sin(2 * np.pi * 8 * t)) * (.25 + .5 * rise)
        s = hum + shimmer(t, 1900 + 1700 * rise, .35) * rise + lowpass(noise(t), 5) * rise * .25
    elif name == 'feather_launch':   # a feather leaves the wing: a hard air crack and a rising whistle
        late = np.maximum(t - .02, 0)
        s = crack(t, 40) * .8 + whoosh(t, .09, .06, 8) * 1.1 + np.sin(2 * np.pi * (1500 + 2600 * late) * late) * np.exp(-late * 22) * .3 * (t >= .02)
    elif name == 'feather_stick':    # it bites into stone: a short dull thock with a ringing, glassy tail
        s = thud(t, 120, 38) * 1.1 + crack(t, 80) * .9 + shimmer(t, 2800, .22) * np.exp(-t * 14) + np.sin(2 * np.pi * 1180 * t) * np.exp(-t * 20) * .2
    elif name == 'feather_hit':      # the stuck feather bursts: void rushing out, a low pulse
        s = thud(t, 58, 9) * 1.0 + lowpass(noise(t), 6) * np.exp(-t * 11) * .6 + shimmer(t, 2300, .25) * np.exp(-t * 9) + crack(t, 30) * .5
    elif name == 'rain':             # a sheet of feathers coming down: dense hiss, falling pitch
        env = np.clip(t / .15, 0, 1) * np.exp(-t * 2.2)
        s = bandpass(noise(t), 3, 14) * env * 1.2 + shimmer(t, 3100 - 900 * p, .18) * env + lowpass(noise(t), 25) * env * .3
    elif name == 'blast':            # a wing slam: low boom, a bright crack, the air pushed out
        s = thud(t, 44, 6.5) * 1.8 + crack(t, 22) * 1.0 + whoosh(t, .12, .09, 9) * .8 + shimmer(t, 1500, .2) * np.exp(-t * 7)
    elif name == 'roar':             # a cry of pain and rage: a hoarse, falling shriek with a tail of metal
        f = 880 * np.exp(-t * 1.6) + 250
        s = np.sin(2 * np.pi * np.cumsum(f) / RATE + 5 * np.sin(2 * np.pi * 31 * t)) * np.exp(-t * 2.2) * .6             + lowpass(noise(t), 4) * np.exp(-t * 2.0) * .5 + shimmer(t, 1700, .25) * np.exp(-((t - .3) / .4) ** 2)
    elif name == 'pillar_crack':     # stone failing: slow cracks and grit
        s = crack(t, 18) * .8
        for k in range(6):
            at = .05 + k * .09 + rng.uniform(0, .04)
            tt = np.maximum(t - at, 0)
            s += crack(tt, 70) * (t >= at) * rng.uniform(.3, .8) + np.sin(2 * np.pi * rng.uniform(300, 900) * tt) * np.exp(-tt * 60) * (t >= at) * .15
    elif name == 'pillar_break':     # the pillar bursts: a huge boom, grinding blocks, rubble skittering
        s = thud(t, 38, 3.8) * 2.0 + crack(t, 9) * 1.1 + lowpass(noise(t), 9) * np.exp(-t * 3.2) * .7
        for k in range(18):
            at = .2 + k * .055 + rng.uniform(0, .04)
            if at < seconds - .06:
                tt = np.maximum(t - at, 0)
                s += thud(tt, rng.uniform(70, 160), 26) * (t >= at) * rng.uniform(.15, .45) + crack(tt, 90) * (t >= at) * .2
    elif name == 'finisher':         # the last blow: a white crack, a sub drop, shards ringing out
        s = crack(t, 14) * 1.2 + thud(t, 40, 4.5) * 2.0 + shimmer(t, 2600, .5) * np.exp(-t * 4.5) + np.sin(2 * np.pi * (2200 - 1400 * p) * t) * np.exp(-t * 9) * .3
    else:
        raise ValueError(name)
    s = np.tanh(s * 1.2)
    s *= (.5 if name != 'breath' else .22) / max(float(np.abs(s).max()), 1e-9)
    s *= np.minimum((1 - p) * 40, 1) * np.minimum(t * 600, 1)
    with wave.open(str(ROOT / f'sky_cleaver_{name}.wav'), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((s * 32767).astype('<i2').tobytes())


for name, seconds in [('wing_soft', .35), ('wing_strong', .45), ('takeoff', .6), ('land', .5), ('bead', .4), ('crash', .9), ('breath', 1.8), ('hit', .2), ('charge', .9), ('feather_launch', .3), ('feather_stick', .35), ('feather_hit', .6), ('rain', 1.2), ('blast', .8), ('roar', 1.2), ('pillar_crack', .7), ('pillar_break', 1.8), ('finisher', 1.1)]:
    make(name, seconds)
print('Sky Cleaver: eighteen spatial creature cues')
