#!/usr/bin/env python3
"""Synthesised placeholder sounds of the talismans (docs/talisman_konzept.md) -> assets/audio/talisman/:
equip_silver (a high, bright tick of a fine chain and a small bell), equip_gold (warmer, a soft ring), equip_voidsteel (dull, with a low violet hum), off (a short quiet
rustle of a chain), absorb (the Schweigtropfen swallow a blow: a deep short bell with a ring),
equip_ravensteel (the Rissfeder: dull chain, a low bell and a dry rustle of feathers), ward (its last wing beat: a hard crack of air, a low thump and falling feather noise),
ward_ready (the feather has gathered itself again: a soft rising shimmer). Deterministic; the sounds of the Rissfeder come last so the older ones stay as they were."""
import numpy as np, wave, os
R = 44100
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "talisman")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(23)

def T(sec): return np.arange(int(R * sec)) / R

def save(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.7
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")

def bell(f, t, decay):
    return np.sin(2 * np.pi * f * t) * np.exp(-t * decay) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * decay * 1.8)

def place(buf, x, at):
    i = int(R * at); n = min(len(x), len(buf) - i); buf[i:i + n] += x[:n]

def chain(n, start=0.0, gap=0.035, bright=1.0):
    buf = np.zeros(int(R * (start + gap * n + 0.2)))
    for k in range(n):
        tick = np.diff(lowpass(rng.standard_normal(int(R * 0.03)), 3), prepend=0) * np.exp(-T(0.03) * 140) * (0.5 + 0.5 * rng.random()) * bright
        place(buf, tick, start + k * gap)
    return buf

for name, f, tail in (("silver", 2637, 0.55), ("gold", 1760, 0.8), ("voidsteel", 880, 0.9)):
    t = T(tail + 0.3)
    x = np.zeros(len(t)); place(x, chain(5, 0.0, 0.03, 1.4 if name == "silver" else 0.9), 0.0)
    place(x, bell(f, T(tail), 7.0 if name != "voidsteel" else 4.0) * 0.7, 0.12)
    if name == "voidsteel":
        place(x, np.sin(2 * np.pi * 98 * T(0.9)) * np.exp(-T(0.9) * 3.0) * 0.5, 0.1)
    save("equip_" + name, x)
save("off", chain(4, 0.0, 0.045, 0.8))
t = T(1.1)
a = bell(220, t, 3.2) * 0.9 + np.sin(2 * np.pi * 110 * t) * np.exp(-t * 4.0) * 0.6
a *= 1 - np.exp(-t * 400)
save("absorb", a)

# --- the Rissfeder (docs/rissfeder.md); drawn after everything above, so the older sounds do not change
def feathers(sec, density, bright):
    """A dry rustle: many tiny soft ticks with a falling envelope."""
    n = int(R * sec); buf = np.zeros(n)
    for _ in range(int(density * sec)):
        at = int(n * rng.random() ** 1.4)
        k = int(R * rng.uniform(0.004, 0.012))
        if at + k < n:
            buf[at:at + k] += np.diff(lowpass(rng.standard_normal(k + 1), 2)) * rng.random() * bright * np.exp(-np.arange(k) / (R * 0.004))
    return buf * np.exp(-T(sec) * 3.0)

t = T(1.0)
x = np.zeros(len(t)); place(x, chain(5, 0.0, 0.04, 0.7), 0.0)
place(x, bell(392, T(0.8), 4.5) * 0.6, 0.12)
place(x, np.sin(2 * np.pi * 73 * T(0.9)) * np.exp(-T(0.9) * 3.5) * 0.5, 0.1)
place(x, feathers(0.5, 260, 3.0) * 0.5, 0.05)
save("equip_ravensteel", x)

t = T(1.4)
crack = lowpass(rng.standard_normal(len(t)), 2) * np.exp(-t * 30) * 1.2 * (1 - np.exp(-t * 900))
thump = np.sin(2 * np.pi * (70 - 25 * t) * t) * np.exp(-t * 7) * 1.0
tear = np.sin(2 * np.pi * (2400 - 1900 * np.minimum(t / 0.35, 1.0)) * t) * np.exp(-t * 11) * 0.35 * (1 - np.exp(-t * 600))
x = crack + thump + tear
place(x, feathers(1.0, 520, 4.0) * 0.8, 0.08)
place(x, bell(330, T(1.0), 4.0) * 0.18, 0.04)
save("ward", x)

t = T(1.2)
rise = np.sin(2 * np.pi * (520 + 520 * np.minimum(t / 0.9, 1.0)) * t) * np.sin(np.pi * np.minimum(t / 1.2, 1.0)) ** 2 * 0.5
rise += np.sin(2 * np.pi * (780 + 780 * np.minimum(t / 0.9, 1.0)) * t) * np.sin(np.pi * np.minimum(t / 1.2, 1.0)) ** 3 * 0.25
rise *= 1 - np.exp(-t * 40)
x = rise.copy(); place(x, feathers(0.4, 160, 1.4) * 0.35, 0.0)
save("ward_ready", x)
