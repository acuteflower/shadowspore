#!/usr/bin/env python3
"""Synthesised placeholder sounds of the mine (docs/mine.md section 7), numpy + wave only: assets/audio/mine/
  ambience_<zone>.wav (24 s loops, seamless), rumble.wav, creak_a/b.wav, drip_a/b.wav.   Run: python3 tools/audio_mine.py"""
import pathlib
import wave

import numpy as np

SR = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "mine"


def write(name, x):
    OUT.mkdir(parents=True, exist_ok=True)
    x = np.clip(x, -1, 1)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32000).astype("<i2").tobytes())


def filt(noise, lo=None, hi=None, slope=0.0):
    """FFT filter: pass lo..hi Hz, spectral tilt `slope` (0 white, -1 pink, -2 brown)."""
    spec = np.fft.rfft(noise)
    f = np.fft.rfftfreq(len(noise), 1 / SR)
    gain = np.ones_like(f)
    if slope:
        gain *= (np.maximum(f, 20.0) / 100.0) ** (slope / 2)
    if lo:
        gain *= 1 / (1 + (lo / np.maximum(f, 1)) ** 4)
    if hi:
        gain *= 1 / (1 + (f / hi) ** 4)
    return np.fft.irfft(spec * gain, len(noise))


def env(n, attack, release):
    e = np.ones(n)
    a, r = int(attack * SR), int(release * SR)
    if a:
        e[:a] = np.linspace(0, 1, a)
    if r:
        e[-r:] = np.minimum(e[-r:], np.linspace(1, 0, r))
    return e


def add(dst, src, at):
    i = int(at * SR) % len(dst)
    n = min(len(src), len(dst) - i)
    dst[i:i + n] += src[:n]
    if n < len(src):
        dst[:len(src) - n] += src[n:]  # wraps: the loop stays seamless


def drip(rng, pitch=1800, echo=0.25, level=0.25):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = pitch * (1 + 0.25 * np.exp(-t * 40))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 28) * level
    x[:200] += rng.normal(0, 0.05, 200) * np.exp(-np.arange(200) / 40)
    out = np.zeros(int(1.4 * SR))
    for k, d in enumerate((0.0, 0.17, 0.33, 0.52)):
        i = int(d * SR)
        out[i:i + n] += x * (echo ** k)
    return out


def creak(rng, base=170, length=0.7, level=0.2):
    n = int(length * SR)
    t = np.arange(n) / SR
    f = base * (1 - 0.18 * t / length) * (1 + 0.04 * np.sin(2 * np.pi * 11 * t))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    rough = filt(rng.normal(0, 1, n), 300, 1800) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t))
    return (tone * 0.4 + rough * 0.8) * env(n, 0.08, 0.35) * level


def loop(name, seconds, build):
    n = int(seconds * SR)
    rng = np.random.default_rng(abs(hash(name)) % 2**31 if False else sum(map(ord, name)))
    x = build(rng, n)
    fade = int(1.5 * SR)  # the end is mixed into the start: seamless
    x = np.concatenate([x, np.zeros(fade)])
    head = x[:fade] * np.linspace(0, 1, fade)
    x[:fade] = head + x[n:n + fade] * np.linspace(1, 0, fade)
    x = x[:n]
    x /= max(0.001, np.abs(x).max()) / 0.7
    write(name, x)


def base_air(rng, n, level=0.3, cutoff=380):
    x = filt(rng.normal(0, 1, n), None, cutoff, -2)
    x /= np.abs(x).max()
    t = np.arange(n) / SR
    return x * level * (1 + 0.35 * np.sin(2 * np.pi * 0.17 * t + 1.0)) * (1 + 0.15 * np.sin(2 * np.pi * 0.07 * t))


def stollen(rng, n):
    x = base_air(rng, n)
    wind = filt(rng.normal(0, 1, n), 700, 1100) * 0.05
    x += wind * (0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * np.arange(n) / SR))
    for at in (3.1, 9.6, 17.2):
        add(x, creak(rng, base=rng.uniform(150, 210)), at)
    for at in np.cumsum(rng.uniform(3, 6, 6)):
        add(x, drip(rng, rng.uniform(1500, 2300)), at)
    return x


def stein(rng, n):
    x = base_air(rng, n, 0.28, 300)
    t = np.arange(n) / SR
    x += np.sin(2 * np.pi * 55 * t) * 0.05 * (1 + 0.5 * np.sin(2 * np.pi * 0.09 * t))
    for at in np.cumsum(rng.uniform(2.5, 5, 7)):
        add(x, drip(rng, rng.uniform(900, 1500), echo=0.45, level=0.22), at)
    for at in (5.0, 13.5, 20.0):  # stone ticking
        tick = filt(rng.normal(0, 1, int(0.08 * SR)), 500, 3000) * np.exp(-np.arange(int(0.08 * SR)) / 500) * 0.35
        add(x, tick, at)
        add(x, tick * 0.4, at + 0.23)
    return x


def kristall(rng, n):
    x = base_air(rng, n, 0.2, 260)
    t = np.arange(n) / SR
    for f, a in ((392.0, 0.045), (587.3, 0.03), (880.0, 0.02), (1174.7, 0.012)):
        x += np.sin(2 * np.pi * (f * 1.003) * t) * a * (0.6 + 0.4 * np.sin(2 * np.pi * 0.13 * t + f))
        x += np.sin(2 * np.pi * (f * 0.997) * t) * a * (0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t + f * 2))
    for at in np.cumsum(rng.uniform(3, 7, 5)):
        add(x, drip(rng, rng.uniform(2200, 3200), echo=0.5, level=0.2), at)
    return x


def zerfressen(rng, n):
    x = base_air(rng, n, 0.3, 200)
    t = np.arange(n) / SR
    x += np.sin(2 * np.pi * np.cumsum(41 + 3 * np.sin(2 * np.pi * 0.05 * t)) / SR) * 0.12
    x += np.sin(2 * np.pi * np.cumsum(61.5 + 2 * np.sin(2 * np.pi * 0.08 * t + 1)) / SR) * 0.07
    whisper = filt(rng.normal(0, 1, n), 500, 2400) * 0.05
    x += whisper * np.clip(np.sin(2 * np.pi * 0.09 * t) * 1.5, 0, 1) ** 2
    beat = np.zeros(n)
    for at in np.arange(1.0, 24, 3.2):  # a slow heartbeat in the dark
        k = int(0.4 * SR)
        tt = np.arange(k) / SR
        add(beat, np.sin(2 * np.pi * 58 * tt) * np.exp(-tt * 9) * 0.35, at)
        add(beat, np.sin(2 * np.pi * 52 * tt) * np.exp(-tt * 11) * 0.22, at + 0.3)
    return x + beat


def rumble():
    rng = np.random.default_rng(7)
    n = int(3.2 * SR)
    t = np.arange(n) / SR
    x = filt(rng.normal(0, 1, n), None, 140, -1) * (np.exp(-((t - 0.5) / 0.9) ** 2))
    x += filt(rng.normal(0, 1, n), 60, 420) * 0.15 * np.exp(-((t - 0.4) / 0.5) ** 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t))
    for k in range(26):  # pebbles falling afterwards
        at = 0.8 + rng.uniform(0, 2.2)
        click = filt(rng.normal(0, 1, 400), 700, 4000) * np.exp(-np.arange(400) / 70) * rng.uniform(0.05, 0.2)
        i = int(at * SR)
        x[i:i + 400] += click[:max(0, min(400, n - i))] if i + 400 <= n else click[:n - i]
    x /= np.abs(x).max() / 0.85
    write("rumble.wav", x)


def main():
    for name, fn in (("stollen", stollen), ("stein", stein), ("kristall", kristall), ("zerfressen", zerfressen)):
        loop(f"ambience_{name}.wav", 24, fn)
    rumble()
    rng = np.random.default_rng(3)
    write("creak_a.wav", creak(rng, 160, 0.8, 0.5))
    write("creak_b.wav", creak(rng, 210, 0.6, 0.5))
    write("drip_a.wav", drip(rng, 1700, 0.3, 0.6))
    write("drip_b.wav", drip(rng, 2400, 0.35, 0.55))
    print("wrote", sorted(p.name for p in OUT.glob("*.wav")))


if __name__ == "__main__":
    main()
