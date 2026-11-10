"""Turns the raw seed_audio wavs of tools/sfx_manifest.json into assets/audio/sfx/<id>.wav.

    py -3 tools/sfx_process.py <raw_dir> [id ...]

One shared chain for every sound so the set sits together: mono, DC removed, high-pass 70 Hz,
soft low-pass 10.5 kHz, leading silence cut, cut to `max` seconds with a fade, peak -3 dBFS,
then the per-sound `gain` (dB) from the manifest. Needs numpy only.
"""
import json
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "sfx"
RATE = 44100


def read_audio(path: Path) -> tuple[np.ndarray, int]:
	"""wav through the wave module, mp3 (Mirelo clips) through miniaudio (pip install miniaudio)."""
	if path.suffix.lower() == ".mp3":
		import miniaudio
		d = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.SIGNED16, nchannels=1, sample_rate=RATE)
		return np.asarray(d.samples, dtype=np.float64) / 32768.0, RATE
	return read_wav(path)


def read_wav(path: Path) -> tuple[np.ndarray, int]:
	with wave.open(str(path), "rb") as w:
		ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
		raw = w.readframes(n)
	if width == 2:
		data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
	elif width == 3:
		b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
		v = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
		v = np.where(v >= 1 << 23, v - (1 << 24), v)
		data = v.astype(np.float64) / (1 << 23)
	elif width == 4:
		data = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2147483648.0
	else:
		raise ValueError("unsupported sample width %d" % width)
	if ch > 1:
		data = data.reshape(-1, ch).mean(axis=1)
	return data, rate


def resample(x: np.ndarray, rate: int) -> np.ndarray:
	if rate == RATE:
		return x
	n = int(round(len(x) * RATE / rate))
	return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)


def band(x: np.ndarray, hp: float, lp: float) -> np.ndarray:
	n = len(x)
	size = 1 << (n - 1).bit_length()
	spec = np.fft.rfft(x, size)
	f = np.fft.rfftfreq(size, 1.0 / RATE)
	hi = 1.0 / (1.0 + (hp / np.maximum(f, 1e-3)) ** 4)  # 24 dB/oct high-pass
	lo = 1.0 / (1.0 + (f / lp) ** 2)  # 12 dB/oct low-pass
	return np.fft.irfft(spec * hi * lo, size)[:n]


def process(raw: Path, out: Path, max_s: float, gain_db: float, loop: bool = False) -> float:
	x, rate = read_audio(raw)
	return process_array(resample(x, rate), out, max_s, gain_db, loop)


def write(x: np.ndarray, out: Path) -> float:
	x = np.clip(x, -0.98, 0.98)
	pcm = (x * 32767).astype("<i2")
	out.parent.mkdir(parents=True, exist_ok=True)
	with wave.open(str(out), "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(RATE)
		w.writeframes(pcm.tobytes())
	return len(pcm) / RATE


def make_loop(x: np.ndarray, length_s: float, gain_db: float) -> np.ndarray:
	"""Seamless bed: keeps the middle of the clip, then cross-fades its tail into its head (equal power)."""
	cf = int(min(1.0, len(x) / RATE * 0.3) * RATE)
	keep = min(len(x), int(length_s * RATE) + cf)
	x = x[(len(x) - keep) // 2:][:keep]
	body = x[: len(x) - cf].copy()
	t = np.linspace(0, np.pi / 2, cf)
	body[:cf] = body[:cf] * np.sin(t) + x[len(x) - cf:] * np.cos(t)
	return body / np.abs(body).max() * (10 ** (-3 / 20)) * (10 ** (gain_db / 20))


def _runs(x: np.ndarray, env: np.ndarray, thr_db: float, gap_s: float) -> list[list[int]]:
	active = env > env.max() * 10 ** (thr_db / 20)
	runs: list[list[int]] = []
	i, n = 0, len(x)
	gap = int(gap_s * RATE)
	while i < n:
		if active[i]:
			j = i
			last = i
			while j < n and j - last < gap:
				if active[j]:
					last = j
				j += 1
			runs.append([i, last])
			i = last + 1
		else:
			i += 1
	return [r for r in runs if r[1] - r[0] > int(0.03 * RATE)]


def split_clip(x: np.ndarray, count: int) -> list[np.ndarray]:
	"""Cuts a clip holding `count` separate sounds into its pieces. The generator leaves a noise bed instead of true silence,
	so the threshold and the merge gap are searched until exactly `count` runs remain."""
	win = int(0.01 * RATE)
	env = np.sqrt(np.convolve(x * x, np.ones(win) / win, mode="same"))
	best: list[list[int]] = []
	for gap_s in (0.3, 0.45, 0.6, 0.8):
		for thr in (-40, -36, -33, -30, -27, -24, -21, -18):
			runs = _runs(x, env, thr, gap_s)
			if len(runs) == count:
				best = runs
				break
			if not best and len(runs) > count:
				best = runs
		else:
			continue
		break
	runs = best
	if len(runs) > count:  # keep the loudest `count` runs, in time order
		runs = sorted(sorted(runs, key=lambda r: -np.abs(x[r[0]:r[1]]).max())[:count])
	pad = int(0.02 * RATE)
	return [x[max(0, a - pad): b + pad] for a, b in runs]


def process_array(x: np.ndarray, out: Path, max_s: float, gain_db: float, loop: bool = False) -> float:
	x = x - x.mean()
	x = band(x, 70.0, 10500.0)
	if loop:
		return write(make_loop(x, max_s, gain_db), out)
	peak = np.abs(x).max()
	if peak < 1e-5:
		raise ValueError("silent: " + raw.name)
	# smoothed envelope (10 ms RMS): the sound is what stays within 30 dB of its loudest moment, the noise bed round it is cut
	win = int(0.01 * RATE)
	env = np.sqrt(np.convolve(x * x, np.ones(win) / win, mode="same"))
	top = env.max()
	loud = np.nonzero(env > top * 0.0316)[0]  # -30 dB
	start = max(0, int(loud[0]) - int(0.005 * RATE))
	x = x[start:]
	env = env[start:]
	keep = int(max_s * RATE)
	x = x[:keep]
	env = env[:keep]
	loud = np.nonzero(env > top * 0.063)[0]  # -24 dB: the tail ends where it sinks into the noise bed
	x = x[: int(loud[-1]) + 1]
	fade = min(int(0.12 * RATE), len(x) // 3)
	if fade > 1:
		x[-fade:] *= np.cos(np.linspace(0, np.pi / 2, fade)) ** 2
	fin = min(int(0.002 * RATE), len(x) // 4)
	if fin > 1:
		x[:fin] *= np.linspace(0, 1, fin)
	x = x / np.abs(x).max() * (10 ** (-3 / 20)) * (10 ** (gain_db / 20))
	x = np.clip(x, -0.98, 0.98)
	pcm = (x * 32767).astype("<i2")
	out.parent.mkdir(parents=True, exist_ok=True)
	with wave.open(str(out), "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(RATE)
		w.writeframes(pcm.tobytes())
	return len(pcm) / RATE


def main() -> None:
	raw_dir = Path(sys.argv[1])
	only = set(sys.argv[2:])
	manifest = json.loads((ROOT / "tools" / "sfx_manifest.json").read_text(encoding="utf-8"))
	for s in manifest["sounds"]:
		if only and s["id"] not in only:
			continue
		raw = raw_dir / (s["id"] + ".wav")
		if not raw.exists():
			raw = raw_dir / (s["id"] + ".mp3")
		if not raw.exists():
			continue
		secs = process(raw, OUT / (s["id"] + ".wav"), float(s["max"]), float(s["gain"]), bool(s.get("loop", False)))
		print("%-16s %.2f s" % (s["id"], secs))
	by_id = {s["id"]: s for s in manifest["sounds"]}
	for pack in manifest.get("packs", []):  # one clip with several sounds in a row, cut apart on the silences
		raw = raw_dir / (pack["raw"] + ".wav")
		if not raw.exists() or (only and not only & set(pack["ids"])):
			continue
		x, rate = read_audio(raw)
		pieces = split_clip(resample(x, rate) - x.mean(), len(pack["ids"]))
		print("pack %s: %d pieces for %d ids" % (pack["raw"], len(pieces), len(pack["ids"])))
		for sid, piece in zip(pack["ids"], pieces):
			if only and sid not in only:
				continue
			spec = by_id[sid]
			secs = process_array(piece, OUT / (sid + ".wav"), float(spec["max"]), float(spec["gain"]))
			print("%-16s %.2f s" % (sid, secs))


if __name__ == "__main__":
	main()
