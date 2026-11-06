"""Quiet menu chimes. Regenerate with python3 tools/audio_skills.py (stdlib only)."""
import math
import random
import struct
import wave
from pathlib import Path


def main() -> None:
    output = Path(__file__).resolve().parents[1] / "assets/audio/skills"
    output.mkdir(parents=True, exist_ok=True)
    rate = 22050
    sounds = [
        ("open", 0.8, [146.83, 220.0, 293.66]),
        ("focus", 0.13, [660.0]),
        ("reveal", 1.4, [220.0, 329.63, 440.0, 659.26]),
    ]
    for name, duration, notes in sounds:
        rng = random.Random(42)
        samples = []
        for i in range(int(rate * duration)):
            time = i / rate
            value = 0.0
            for j, frequency in enumerate(notes):
                age = time - j * (0.12 if name == "reveal" else 0.035)
                if age < 0:
                    continue
                envelope = (1 - math.exp(-age * 45)) * math.exp(-age * (4.5 if name == "focus" else 3.2))
                value += (math.sin(math.tau * frequency * age) + 0.18 * math.sin(math.tau * frequency * 2.003 * age)) * envelope / len(notes)
            value += (rng.random() * 2 - 1) * 0.025 * math.sin(math.pi * time / duration) ** 2
            value *= min(1.0, (duration - time) / 0.07) * 0.5
            samples.append(struct.pack("<h", round(max(-1, min(1, value)) * 32767)))
        with wave.open(str(output / (name + ".wav")), "wb") as sound:
            sound.setparams((1, 2, rate, 0, "NONE", "not compressed"))
            sound.writeframes(b"".join(samples))


if __name__ == "__main__":
    main()
