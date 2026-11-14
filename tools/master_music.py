#!/usr/bin/env python3
"""Masters raw music tracks (from `tools/music_raw/`) into seamlessly looping,
loudness-matched `.ogg` files in `assets/audio/music/`.

Modes:
  - Exploration (`day`, `night`, `hexenwald`, `desert`): 4.0s equal-power crossfade loop, -16.5 dBFS RMS.
  - Action (`combat`, `boss`): Preserves 100% of the 0:00 opening impact (since MusicDirector
    restarts fights from 0:00!) while folding the ending reverb tail cleanly over bar 1 for
    gapless looping, at -14.8 dBFS RMS.
"""
import sys
from pathlib import Path
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tools" / "music_raw"
OUT_DIR = ROOT / "assets" / "audio" / "music"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def master_loop(
    in_path: Path,
    out_path: Path,
    action_mode: bool = False,
    playlist_mode: bool = False,
    target_rms_db: float = -16.5,
) -> None:
    audio, sr = sf.read(str(in_path), always_2d=True, dtype="float64")
    env = np.max(np.abs(audio), axis=1)

    if action_mode:
        # Start right on the first transient (keep only 15ms pre-roll) so fights hit immediately!
        active_start = np.where(env > 0.008)[0]
        start_idx = max(0, int(active_start[0]) - int(0.015 * sr)) if len(active_start) > 0 else 0
        # Trim dead silence at the end where final reverb tail drops below ~ -38 dB
        active_end = np.where(env > 0.012)[0]
        tail_keep = int(1.6 * sr)
        end_idx = min(len(audio), int(active_end[-1]) + tail_keep) if len(active_end) > 0 else len(audio)
        audio = audio[start_idx:end_idx]

        # Fold the 1.6s reverb tail over the opening bar while keeping 0:00 at full punch
        ov_n = min(tail_keep, len(audio) // 8)
        if ov_n > 0:
            tail = audio[-ov_n:].copy()
            body = audio[:-ov_n].copy()
            # Smooth tail fade-in/out so adding it to `body[:ov_n]` has zero seam at sample 0
            tail_env = np.sin(0.5 * np.pi * np.linspace(1.0, 0.0, ov_n))[:, None]
            att_n = min(int(0.025 * sr), ov_n // 4)
            body[:att_n] *= np.linspace(0.0, 1.0, att_n)[:, None]
            tail[:att_n] *= np.linspace(0.0, 1.0, att_n)[:, None]
            body[:ov_n] += tail * tail_env * 0.85
            # Tiny 15ms cosine polish at the very end of `body` so `body[-1] -> body[0]` = 0.0!
            end_fade = min(int(0.018 * sr), len(body) // 10)
            body[-end_fade:] *= np.linspace(1.0, 0.0, end_fade)[:, None]
            audio = body
    elif playlist_mode:
        # Preserve full opening & natural concert ending for multi-track biome playlists!
        active = np.where(env > 0.0012)[0]
        if len(active) > 0:
            start_idx = max(0, int(active[0]) - int(0.04 * sr))
            end_idx = min(len(audio), int(active[-1]) + int(0.35 * sr))
            audio = audio[start_idx:end_idx]
        head_n = min(int(0.025 * sr), len(audio) // 16)
        tail_n = min(int(0.45 * sr), len(audio) // 12)
        if head_n > 0:
            audio[:head_n] *= (0.5 - 0.5 * np.cos(np.pi * np.linspace(0.0, 1.0, head_n)))[:, None]
        if tail_n > 0:
            audio[-tail_n:] *= (0.5 + 0.5 * np.cos(np.pi * np.linspace(0.0, 1.0, tail_n)))[:, None]
    else:
        active = np.where(env > 0.0018)[0]
        if len(active) > 0:
            start_idx = max(0, int(active[0]) - int(0.06 * sr))
            end_idx = min(len(audio), int(active[-1]) + int(0.10 * sr))
            audio = audio[start_idx:end_idx]

        xf_n = min(int(4.0 * sr), len(audio) // 6)
        if xf_n > 0:
            head = audio[:xf_n].copy()
            tail = audio[-xf_n:].copy()
            body = audio[xf_n:-xf_n].copy()
            fade_in = np.sin(0.5 * np.pi * np.linspace(0.0, 1.0, xf_n))[:, None]
            fade_out = np.cos(0.5 * np.pi * np.linspace(0.0, 1.0, xf_n))[:, None]
            audio = np.vstack((head * fade_in + tail * fade_out, body))

    # Loudness match with transparent soft-knee peak ceiling (-0.9 dBFS)
    cur_rms = float(np.sqrt(np.mean(audio ** 2)) + 1e-12)
    target_rms = 10.0 ** (target_rms_db / 20.0)
    audio = audio * (target_rms / cur_rms)

    ceiling = 0.901  # -0.9 dBFS
    peak = float(np.max(np.abs(audio)))
    if peak > ceiling:
        thresh = 0.68
        mag = np.abs(audio)
        over = np.maximum(0.0, mag - thresh)
        compressed = thresh + (ceiling - thresh) * np.tanh(over / max(ceiling - thresh, 1e-6))
        scale = np.where(mag > thresh, compressed / np.maximum(mag, 1e-12), 1.0)
        audio = audio * scale

    data32 = audio.astype(np.float32)
    chunk = 32768
    with sf.SoundFile(str(out_path), mode="w", samplerate=sr, channels=data32.shape[1], format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(data32), chunk):
            f.write(data32[i:i + chunk])

    final_rms_db = 20.0 * np.log10(float(np.sqrt(np.mean(data32 ** 2))) + 1e-12)
    seam = float(np.max(np.abs(data32[0] - data32[-1])))
    mode_tag = "ACTION" if action_mode else ("PLAYLIST" if playlist_mode else "EXPLORE")
    print(
        f"[{mode_tag}] Mastered {in_path.name} -> {out_path.name}: {len(data32)/sr:.2f}s @ {sr} Hz, "
        f"RMS={final_rms_db:.1f} dBFS, peak={np.max(np.abs(data32)):.3f}, loop_seam={seam:.5f}",
        flush=True,
    )


def main() -> None:
    src_name = sys.argv[1]
    dst_name = sys.argv[2]
    action = "--action" in sys.argv
    playlist = "--playlist" in sys.argv
    rms = -14.8 if action else -16.5
    src = Path(src_name) if Path(src_name).exists() else (RAW_DIR / src_name)
    dst = OUT_DIR / dst_name
    master_loop(src, dst, action_mode=action, playlist_mode=playlist, target_rms_db=rms)


if __name__ == "__main__":
    main()
