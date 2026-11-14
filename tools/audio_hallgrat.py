#!/usr/bin/env python3
"""Synthesised placeholder sounds of Hallgrat and the Westweg (docs/stadt_westen_konzept.md 5 "Klang", 8.1) -> assets/audio/hallgrat/:
tone_0 .. tone_3 (the town's motif: four notes that only the guide stones' Klangstein carries; a stone hums its note under a glassy ring,
with a slow beat, so it sounds like stone and crystal at once), tone_dead (a dead crystal: a dull knock with a breath of the note in it) and
touch (a palm laid on old stone: grit, a soft thump). Placeholders, no external recordings: `py -3 tools/audio_hallgrat.py`."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "hallgrat")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(41)
MOTIF = [293.66, 392.00, 349.23, 440.00]  # D4 G4 F4 A4: rising, a step back, then open (the order of the motif is 0 1 2 3)


def save(name, x, peak=0.7):
    x = x / max(np.abs(x).max(), 1e-6) * peak
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def smooth(x, n):
    return np.convolve(x, np.ones(n) / n, mode="same")


def tt(seconds):
    return np.arange(int(R * seconds)) / R


def tone(f, seed):
    r = np.random.default_rng(seed)
    t = tt(3.2)
    swell = (1 - np.exp(-t * 9)) * np.exp(-t * 0.95)
    hum = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.001 * t + 0.4) + 0.12 * np.sin(2 * np.pi * f * 3.0 * t + 1.1)
    hum *= swell * (1.0 + 0.12 * np.sin(2 * np.pi * 1.7 * t))  # the slow beat of a stone that rings
    glass = np.zeros(len(t))
    for ratio, amp, decay in ((4.0, 0.22, 2.6), (5.43, 0.12, 3.8), (8.1, 0.06, 6.0)):
        glass += amp * np.sin(2 * np.pi * f * ratio * t + r.uniform(0, 6)) * np.exp(-t * decay)
    strike = smooth(r.standard_normal(len(t)), 3) * np.exp(-t * 70) * 0.25
    return hum * 0.8 + glass + strike


for i, f in enumerate(MOTIF):
    save("tone_%d" % i, tone(f, 10 + i), 0.55)

t = tt(1.0)
knock = np.sin(2 * np.pi * 160 * t) * np.exp(-t * 26) + smooth(rng.standard_normal(len(t)), 8) * np.exp(-t * 45) * 0.6
knock += 0.12 * np.sin(2 * np.pi * MOTIF[0] * t) * (1 - np.exp(-t * 20)) * np.exp(-t * 3.5)
save("tone_dead", knock, 0.5)

t = tt(0.5)
grit = smooth(rng.standard_normal(len(t)), 2) * np.exp(-t * 18) * (0.4 + 0.6 * rng.random(len(t)) ** 6)
thump = np.sin(2 * np.pi * 90 * t) * np.exp(-t * 30)
save("touch", grit * 0.5 + thump, 0.45)
print("hallgrat sounds written to", os.path.normpath(out))


def bell(f, seed):
    """The town's bell in the moon tower: a big bronze bell, struck three times at dusk (hum, prime, tierce, quint, nominal, a long ring)."""
    r = np.random.default_rng(seed)
    t = tt(7.5)
    x = np.zeros(len(t))
    for k, at in enumerate((0.0, 2.2, 4.4)):
        s = np.clip(t - at, 0, None)
        on = (t >= at).astype(float)
        for ratio, amp, decay in ((0.5, 0.55, 0.35), (1.0, 1.0, 0.55), (1.19, 0.45, 0.9), (1.5, 0.35, 1.1), (2.0, 0.4, 1.4), (2.51, 0.2, 2.0)):
            x += on * amp * np.sin(2 * np.pi * f * ratio * s + r.uniform(0, 6)) * np.exp(-s * decay) * (1.0 + 0.06 * np.sin(2 * np.pi * 1.3 * s))
        x += on * smooth(r.standard_normal(len(t)), 4) * np.exp(-s * 40) * 0.3
    return x


save("glocke", bell(146.83, 7), 0.6)  # a low D, the motif's first note an octave down
print("hallgrat bell written")
