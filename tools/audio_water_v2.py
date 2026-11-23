#!/usr/bin/env python3
"""Seamless Water System v2 ambient audio loops (pure numpy + stdlib wave).

Outputs (22050 Hz, 1-channel, 16-bit signed little-endian PCM, NO endpoint fade-to-zero):
  assets/audio/water/brook_loop.wav        12.0 s forest brook (stream body, pebble babble, shimmer, wrapped bubbles/pier gurgles)
  assets/audio/water/surf_wash_loop.wav    12.0 s steady coastal surf wash (NO slow macro-LFO; modulated at runtime by WaterRules.swash_phase)
  assets/audio/water/ocean_swell_loop.wav  16.0 s two-layer crossed open-ocean swell & crest spray

Includes a built-in post-write verification suite reading all 3 WAVs from disk.
"""
from __future__ import annotations

from pathlib import Path
import sys
import wave
import numpy as np

RATE = 22050
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio" / "water"


def smooth_band(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    """Periodic 4th-order Butterworth-like frequency-domain bandpass with zero DC."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    g = 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4) / (1.0 + (f / hi) ** 4)
    g[0] = 0.0
    return np.fft.irfft(spec * g, len(x))


def swell(t: np.ndarray, length_s: float, cycles: int, phase: float, depth: float) -> np.ndarray:
    """Exact integer-cycle periodic amplitude modulation with non-zero floor."""
    if not isinstance(cycles, int) or cycles < 1:
        raise ValueError(f"cycles must be a positive int for exact periodicity, got {cycles!r}")
    return 1.0 - depth + depth * np.sin(2.0 * np.pi * (t / length_s * cycles) + phase)


def loop_place(dst: np.ndarray, src: np.ndarray, at_sample: int) -> None:
    """Adds transient `src` into `dst` at `at_sample`, wrapping modulo len(dst)."""
    idx = (int(at_sample) + np.arange(len(src))) % len(dst)
    np.add.at(dst, idx, src)


def save_wav(path: Path, sig: np.ndarray, peak: float) -> None:
    """Removes DC, normalizes to `peak`, quantizes <i2 PCM with NO endpoint fade."""
    sig = sig - np.mean(sig)
    sig = sig / (float(np.max(np.abs(sig))) + 1e-9) * peak
    pcm = np.rint(np.clip(sig, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def synth_brook_loop() -> np.ndarray:
    length_s = 12.0
    n = int(round(RATE * length_s))
    t = np.arange(n, dtype=np.float64) / RATE
    rng = np.random.default_rng(3101)

    body = smooth_band(rng.standard_normal(n), 110.0, 360.0) * 0.28 * swell(t, length_s, 3, 0.2, 0.12)
    babble = smooth_band(rng.standard_normal(n), 580.0, 2600.0) * 0.44 * swell(t, length_s, 4, 1.1, 0.14)
    shimmer = smooth_band(rng.standard_normal(n), 2400.0, 5400.0) * 0.18 * swell(t, length_s, 5, 2.3, 0.15)
    out = body + babble + shimmer

    # ~380 upward-chirped water droplets placed via stratified jitter + % N wrap
    n_droplets = 380
    for i in range(n_droplets):
        at = int(((i + rng.uniform(0.08, 0.92)) / n_droplets) * n) % n
        dur_s = rng.uniform(0.012, 0.032)
        m = max(16, int(round(dur_s * RATE)))
        k = np.arange(m, dtype=np.float64) / RATE
        f0 = rng.uniform(420.0, 1800.0)
        sweep = rng.uniform(120.0, 450.0)
        freq_inst = f0 + sweep * (k / dur_s)
        phase = 2.0 * np.pi * np.cumsum(freq_inst) / RATE
        env = (np.sin(np.pi * np.arange(m, dtype=np.float64) / m) ** 1.5) * np.exp(-k * 65.0)
        amp = rng.uniform(0.14, 0.28)
        loop_place(out, np.sin(phase) * env * amp, at)

    # ~180 hollow pier-lap gurgles placed via stratified jitter + % N wrap
    n_gurgles = 180
    for i in range(n_gurgles):
        at = int(((i + rng.uniform(0.08, 0.92)) / n_gurgles) * n) % n
        dur_s = rng.uniform(0.025, 0.055)
        m = max(24, int(round(dur_s * RATE)))
        k = np.arange(m, dtype=np.float64) / RATE
        f0 = rng.uniform(220.0, 520.0)
        mod = 1.0 + 0.14 * np.sin(2.0 * np.pi * rng.uniform(28.0, 52.0) * k)
        phase = 2.0 * np.pi * np.cumsum(f0 * mod) / RATE
        env = np.sin(np.pi * np.arange(m, dtype=np.float64) / m) ** 1.3
        amp = rng.uniform(0.10, 0.22)
        loop_place(out, np.sin(phase) * env * amp, at)

    return out


def synth_surf_wash_loop() -> np.ndarray:
    """Steady spectral surf texture: NO slow macro-LFO and NO endpoint fade-to-zero."""
    length_s = 12.0
    n = int(round(RATE * length_s))
    rng = np.random.default_rng(3102)

    low_wash = smooth_band(rng.standard_normal(n), 95.0, 290.0) * 0.30
    surf_body = smooth_band(rng.standard_normal(n), 300.0, 2200.0) * 0.56
    lace_fizz = smooth_band(rng.standard_normal(n), 2200.0, 6600.0) * 0.32
    out = low_wash + surf_body + lace_fizz

    # ~1400 uniform micro-foam effervescence ticks on a stratified-jittered grid
    n_ticks = 1400
    for i in range(n_ticks):
        at = int(((i + rng.uniform(0.1, 0.9)) / n_ticks) * n) % n
        dur_s = rng.uniform(0.003, 0.008)
        m = max(8, int(round(dur_s * RATE)))
        k = np.arange(m, dtype=np.float64) / RATE
        f0 = rng.uniform(1800.0, 5500.0)
        # Smooth attack on sample 0 so tick energy ramps cleanly without harsh impulse
        attack = np.minimum(1.0, np.arange(m, dtype=np.float64) / 3.0)
        tick = np.sin(2.0 * np.pi * f0 * k) * np.exp(-k * 900.0) * attack * rng.uniform(0.05, 0.11)
        loop_place(out, tick, at)

    return out


def synth_ocean_swell_loop() -> np.ndarray:
    length_s = 16.0
    n = int(round(RATE * length_s))
    t = np.arange(n, dtype=np.float64) / RATE
    rng = np.random.default_rng(3103)

    sw_primary = swell(t, length_s, 4, 0.3, 0.32)
    sw_crossed = swell(t, length_s, 3, 1.4, 0.28)
    sw_spray = swell(t, length_s, 4, 0.3, 0.35) ** 1.5

    deep_swell = smooth_band(rng.standard_normal(n), 48.0, 210.0) * 0.68 * sw_primary
    crossed_rush = smooth_band(rng.standard_normal(n), 210.0, 1150.0) * 0.38 * sw_crossed
    crest_spray = smooth_band(rng.standard_normal(n), 1150.0, 3200.0) * 0.14 * sw_spray
    return deep_swell + crossed_rush + crest_spray


def _rms(a: np.ndarray) -> float:
    return float(np.sqrt(np.mean(a * a)))


def verify_wav(path: Path, expected_len_s: float, mode: str) -> dict[str, float]:
    with wave.open(str(path), "rb") as w:
        nch = w.getnchannels()
        sw = w.getsampwidth()
        fr = w.getframerate()
        nf = w.getnframes()
        ct = w.getcomptype()
        raw = w.readframes(nf)

    expected_n = int(round(expected_len_s * RATE))
    assert nch == 1, f"{path.name}: nchannels={nch} != 1"
    assert sw == 2, f"{path.name}: sampwidth={sw} != 2"
    assert fr == RATE, f"{path.name}: framerate={fr} != {RATE}"
    assert ct == "NONE", f"{path.name}: comptype={ct} != NONE"
    assert nf == expected_n, f"{path.name}: nframes={nf} != {expected_n}"

    pcm = np.frombuffer(raw, dtype="<i2")
    assert len(pcm) == nf
    assert int(pcm.min()) > -32768, f"{path.name}: negative clip ({pcm.min()})"
    assert int(pcm.max()) < 32767, f"{path.name}: positive clip ({pcm.max()})"

    x = pcm.astype(np.float64) / 32767.0
    peak = float(np.max(np.abs(x)))
    dc = abs(float(np.mean(x)))
    assert 0.35 <= peak <= 0.65, f"{path.name}: peak={peak:.4f} out of [0.35, 0.65]"
    assert dc < 5e-4, f"{path.name}: dc={dc:.6e} >= 5e-4"

    diffs = np.abs(np.diff(x))
    wrap_jump = abs(float(x[0] - x[-1]))
    assert wrap_jump <= float(np.max(diffs)), f"{path.name}: wrap_jump={wrap_jump:.5f} > max_diff={np.max(diffs):.5f}"
    assert wrap_jump <= 4.0 * float(np.std(diffs)), (
        f"{path.name}: wrap_jump={wrap_jump:.5f} > 4*std(diff)={4.0 * np.std(diffs):.5f}"
    )

    d2 = np.diff(x, n=2)
    wrap_d2 = abs(float((x[1] - x[0]) - (x[0] - x[-1])))
    assert wrap_d2 <= 4.0 * float(np.std(d2)), (
        f"{path.name}: wrap_d2={wrap_d2:.5f} > 4*std(d2)={4.0 * np.std(d2):.5f}"
    )

    global_rms = _rms(x)
    head_rms = _rms(x[:1102])
    tail_rms = _rms(x[-1102:])
    edge_ratio_min = 0.30 if mode == "ocean" else 0.60
    assert head_rms >= edge_ratio_min * global_rms, (
        f"{path.name}: head_rms={head_rms:.5f} < {edge_ratio_min} * global_rms={global_rms:.5f}"
    )
    assert tail_rms >= edge_ratio_min * global_rms, (
        f"{path.name}: tail_rms={tail_rms:.5f} < {edge_ratio_min} * global_rms={global_rms:.5f}"
    )

    s_seam = np.concatenate([x[-(nf // 16):], x[: (nf // 16)]])
    seam_rms = _rms(s_seam)

    if mode in ("surf", "brook"):
        step = nf // 8
        slices = [x[i * step : (i + 1) * step] for i in range(8)] + [s_seam]
        slice_rms = [_rms(s) for s in slices]
        min_r, max_r = min(slice_rms), max(slice_rms)
        ratio = min_r / max_r
        if mode == "surf":
            assert ratio >= 0.78, f"{path.name}: 8-slice+seam min/max ratio={ratio:.4f} < 0.78"
            max_dev = max(abs(r - global_rms) / global_rms for r in slice_rms)
            assert max_dev <= 0.15, f"{path.name}: surf slice deviation={max_dev:.4f} > 0.15"
        else:
            assert ratio >= 0.65, f"{path.name}: 8-slice+seam min/max ratio={ratio:.4f} < 0.65"
    elif mode == "ocean":
        win = int(round(4.0 * RATE))
        slices = [x[i * win : (i + 1) * win] for i in range(4)] + [
            np.concatenate([x[-(win // 2):], x[: (win // 2)]])
        ]
        slice_rms = [_rms(s) for s in slices]
        min_r, max_r = min(slice_rms), max(slice_rms)
        ratio = min_r / max_r
        assert ratio >= 0.75, f"{path.name}: 4s-window+seam min/max ratio={ratio:.4f} < 0.75"
        sec = RATE
        sec_rms = [_rms(x[i * sec : (i + 1) * sec]) for i in range(16)]
        assert min(sec_rms) >= 0.35 * global_rms, (
            f"{path.name}: min 1s slice rms={min(sec_rms):.5f} < 0.35 * global_rms={global_rms:.5f}"
        )
    else:
        raise ValueError(mode)

    return {
        "nframes": float(nf),
        "peak": peak,
        "dc": dc,
        "wrap_jump": wrap_jump,
        "wrap_d2": wrap_d2,
        "global_rms": global_rms,
        "head_rms": head_rms,
        "tail_rms": tail_rms,
        "seam_rms": seam_rms,
        "min_slice_rms": min_r,
        "max_slice_rms": max_r,
        "slice_ratio": ratio,
    }


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    specs = [
        ("brook_loop.wav", synth_brook_loop(), 0.48, 12.0, "brook"),
        ("surf_wash_loop.wav", synth_surf_wash_loop(), 0.48, 12.0, "surf"),
        ("ocean_swell_loop.wav", synth_ocean_swell_loop(), 0.50, 16.0, "ocean"),
    ]
    for fname, sig, peak_target, len_s, mode in specs:
        out_path = OUT_DIR / fname
        save_wav(out_path, sig, peak_target)
        m = verify_wav(out_path, len_s, mode)
        print(
            f"[PASS] {fname}: nframes={int(m['nframes'])}, peak={m['peak']:.4f}, "
            f"dc={m['dc']:.2e}, wrap_jump={m['wrap_jump']:.5f}, wrap_d2={m['wrap_d2']:.5f}, "
            f"global_rms={m['global_rms']:.4f}, head={m['head_rms']:.4f}, tail={m['tail_rms']:.4f}, "
            f"seam={m['seam_rms']:.4f}, slice_rms=[{m['min_slice_rms']:.4f}, {m['max_slice_rms']:.4f}] "
            f"(ratio={m['slice_ratio']:.3f})"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
