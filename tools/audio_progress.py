"""Quiet chimes of the Fortschritt window. Regenerate with python3 tools/audio_progress.py (stdlib only)."""
import math
import random
import struct
import wave
from pathlib import Path


def main() -> None:
    output = Path(__file__).resolve().parents[1] / "assets/audio/progress"
    output.mkdir(parents=True, exist_ok=True)
    rate = 22050
    # name, duration, notes, gap between notes, decay
    sounds = [
        ("open", 1.0, [130.81, 196.0, 261.63, 392.0], 0.06, 3.0),
        ("focus", 0.12, [587.33], 0.0, 5.0),
        ("ready", 1.2, [523.25, 783.99], 0.14, 3.6),
        ("claim", 1.9, [261.63, 329.63, 392.0, 523.25, 659.26, 783.99], 0.11, 2.6),
        ("milestone", 2.6, [196.0, 293.66, 392.0, 493.88, 587.33, 783.99, 987.77], 0.16, 2.0),
    ]
    for name, duration, notes, gap, decay in sounds:
        rng = random.Random(7)
        samples = []
        for i in range(int(rate * duration)):
            time = i / rate
            value = 0.0
            for j, frequency in enumerate(notes):
                age = time - j * gap
                if age < 0:
                    continue
                envelope = (1 - math.exp(-age * 50)) * math.exp(-age * decay)
                value += (math.sin(math.tau * frequency * age) + 0.22 * math.sin(math.tau * frequency * 2.004 * age)
                          + 0.08 * math.sin(math.tau * frequency * 3.01 * age)) * envelope / len(notes) ** 0.7
            value += (rng.random() * 2 - 1) * 0.02 * math.sin(math.pi * time / duration) ** 2
            value *= min(1.0, (duration - time) / 0.08) * 0.5
            samples.append(struct.pack("<h", round(max(-1, min(1, value)) * 32767)))
        with wave.open(str(output / (name + ".wav")), "wb") as sound:
            sound.setparams((1, 2, rate, 0, "NONE", "not compressed"))
            sound.writeframes(b"".join(samples))


if __name__ == "__main__":
    main()
