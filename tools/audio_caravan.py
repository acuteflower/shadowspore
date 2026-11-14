#!/usr/bin/env python3
"""Synthesised placeholder sounds of the travelling merchant's caravan (docs/haendler_konzept.md 9) -> assets/audio/caravan/:
bell_a/bell_b (the wagon's bell, heard from far away), wheels (a seamless loop: rumble of the wheels, creak of the axle), ox_snort, ox_low (a low moo),
ox_bells (the little bells on the yoke at a step), flap (the counter falls down onto its legs), cloth (the canvas pulled out into the awning),
chain (the sign hung up), knock (knocking on the wagon at night). Placeholders, no external recordings: `py -3 tools/audio_caravan.py`."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "caravan")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(23)


def save(name, x, peak=0.7):
    x = x / max(np.abs(x).max(), 1e-6) * peak
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def smooth(x, n):
    return np.convolve(x, np.ones(n) / n, mode="same")


def tt(seconds):
    return np.arange(int(R * seconds)) / R


def bell(base, seed):
    """A small brass bell: inharmonic partials, a bright strike, a long ring with a slow beat."""
    r = np.random.default_rng(seed)
    t = tt(1.8)
    x = np.zeros(len(t))
    for ratio, amp, decay in ((1.0, 1.0, 2.2), (2.76, 0.55, 3.4), (5.40, 0.3, 5.0), (8.93, 0.16, 7.0), (1.008, 0.6, 2.4)):
        x += amp * np.sin(2 * np.pi * base * ratio * t + r.uniform(0, 6)) * np.exp(-t * decay)
    x += 0.4 * r.standard_normal(len(t)) * np.exp(-t * 90)  # the clapper's strike
    x *= 1.0 + 0.08 * np.sin(2 * np.pi * 3.1 * t)
    return x


save("bell_a", bell(1180, 1))
save("bell_b", bell(1320, 2))

# wheels: a loop of 1.6 s; rumble (filtered noise with a wheel-turn pulse), wood knocks of the spokes on stones, a creaking axle
t = tt(1.6)
n = smooth(rng.standard_normal(len(t)), 40) - smooth(rng.standard_normal(len(t)), 400)
pulse = 0.65 + 0.35 * np.sin(2 * np.pi * (1 / 0.8) * t) ** 2
x = n * pulse * 1.2
for k in range(7):
    at = int(rng.uniform(0, 1.55) * R)
    m = min(int(R * 0.05), len(t) - at)
    s = np.arange(m) / R
    x[at:at + m] += np.sin(2 * np.pi * rng.uniform(140, 260) * s) * np.exp(-s * 60) * rng.uniform(0.5, 1.0)
creak_f = 520 + 90 * np.sin(2 * np.pi * 0.625 * t)
phase = np.cumsum(creak_f) / R * 2 * np.pi
creak = np.sign(np.sin(phase)) * 0.12 * np.clip(np.sin(2 * np.pi * 0.625 * t + 1.0), 0, 1) ** 4
x += smooth(creak, 6)
fade = int(R * 0.03)  # make the ends meet
x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
x = x[:-fade]
save("wheels", x, 0.55)

# the ox
t = tt(0.55)
snort = smooth(rng.standard_normal(len(t)), 8) * np.exp(-((t - 0.12) / 0.09) ** 2) + 0.6 * smooth(rng.standard_normal(len(t)), 14) * np.exp(-((t - 0.34) / 0.07) ** 2)
save("ox_snort", snort)
t = tt(1.4)
f0 = 92 + 18 * np.sin(np.pi * t / 1.4) - 10 * t
ph = np.cumsum(f0) / R * 2 * np.pi
low = sum(np.sin(ph * k) / k ** 1.2 for k in range(1, 9)) * np.sin(np.pi * t / 1.4) ** 0.7
low += 0.15 * smooth(rng.standard_normal(len(t)), 30)
save("ox_low", low, 0.6)
t = tt(0.5)
jingle = np.zeros(len(t))
for k in range(3):
    at = int(k * 0.06 * R)
    s = t[: len(t) - at]
    jingle[at:] += sum(np.sin(2 * np.pi * f * s) for f in (2900 + 120 * k, 4100 + 90 * k)) * np.exp(-s * 14)
save("ox_bells", jingle, 0.4)

# the stall
t = tt(0.4)
flap = (np.sin(2 * np.pi * 95 * t) + 0.6 * np.sin(2 * np.pi * 180 * t)) * np.exp(-t * 18) + 0.5 * smooth(rng.standard_normal(len(t)), 4) * np.exp(-t * 60)
save("flap", flap)
t = tt(0.7)
cloth = (smooth(rng.standard_normal(len(t)), 6) - smooth(rng.standard_normal(len(t)), 50)) * np.sin(np.pi * t / 0.7) ** 0.8 * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t) ** 2)
save("cloth", cloth, 0.5)
t = tt(0.5)
chain = np.zeros(len(t))
for k in range(6):
    at = int(rng.uniform(0, 0.32) * R)
    s = t[: len(t) - at]
    chain[at:] += np.sin(2 * np.pi * rng.uniform(2200, 3600) * s) * np.exp(-s * 45) * rng.uniform(0.4, 1)
save("chain", chain, 0.5)
t = tt(0.75)
knock = np.zeros(len(t))
for at_s in (0.0, 0.22, 0.42):
    at = int(at_s * R)
    s = t[: len(t) - at]
    knock[at:] += (np.sin(2 * np.pi * 150 * s) + 0.5 * np.sin(2 * np.pi * 310 * s)) * np.exp(-s * 40)
save("knock", knock)
print("caravan sounds written to", os.path.abspath(out))
