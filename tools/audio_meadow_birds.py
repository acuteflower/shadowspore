#!/usr/bin/env python3
"""Quiet synthesized placeholder calls (numpy/stdlib), no external recordings.
Barn owl: breathy rasp, not a generic owl hoot. Hoopoe: three rounded, separated notes.
"""
from pathlib import Path
import wave
import numpy as np
ROOT=Path(__file__).resolve().parent.parent/'assets/audio/wildlife';ROOT.mkdir(parents=True,exist_ok=True)
RATE=22050

def write(name,signal):
    signal=signal/(np.max(np.abs(signal))+1e-9)*.4
    with wave.open(str(ROOT/name),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(np.int16(signal*32767).tobytes())

for v in range(2):
    rng=np.random.default_rng(630+v);t=np.arange(int(RATE*(.46+.12*v)))/RATE;u=t/t[-1]
    noise=rng.normal(0,1,len(t));smooth=np.convolve(noise,np.ones(9)/9,mode='same')
    breath=(noise-smooth)*.25+smooth*.85
    env=np.sin(np.pi*u)**1.2
    rasp=(.55+.45*np.sin(t*2*np.pi*45)**2)
    tone=np.sin(2*np.pi*(850*t+35*t*t))*.08
    write(f'owl_{v}.wav',(breath*rasp+tone)*env)
    out=np.zeros(int(RATE*1.02))
    for i,frequency in enumerate([410.,393.,400.]):
        duration=.14+.01*v;t=np.arange(int(RATE*duration))/RATE
        phase=2*np.pi*(frequency*(1+.015*v)*t-10*t*t)
        env=np.sin(np.pi*np.arange(len(t))/(len(t)-1))**.6
        note=(np.sin(phase)+.12*np.sin(2*phase)+.035*np.sin(3*phase))*env
        start=int((.05+i*.29)*RATE);out[start:start+len(note)]+=note
    write(f'hoopoe_{v}.wav',out)
print('Wrote owl and hoopoe placeholder calls')
