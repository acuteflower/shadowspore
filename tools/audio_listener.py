#!/usr/bin/env python3
"""Reproducible quiet creature cues: inhaling tissue, resonant throat and fractured release.
Synthetic placeholders, normalised below full scale; no recordings or external packages beyond numpy.
"""
from pathlib import Path
import wave
import numpy as np

ROOT=Path(__file__).resolve().parent.parent/'assets/audio'
RATE=22050
rng=np.random.default_rng(614)
for kind,seconds in [('charge',.8),('wave',.55),('scream',.6),('death',.8)]:
    t=np.arange(int(RATE*seconds))/RATE;p=t/seconds
    noise=rng.uniform(-1.,1.,len(t))
    soft=np.convolve(noise,np.ones(11)/11,mode='same')
    if kind=='charge':
        phase=2*np.pi*(53*t+47*t*t)
        signal=(np.sin(phase)+.4*np.sin(phase*2.03)+soft*.65)*p**1.4*np.sin(np.pi*np.minimum(p*1.05,1))**.3
    elif kind=='wave':
        phase=2*np.pi*(145*t-95*t*t)
        signal=(np.sin(phase)+.4*np.sin(phase*2.41)+soft*2.)*np.exp(-p*5)*np.minimum(p*45,1)
    elif kind=='scream':
        hit=np.maximum(t-.085,0)
        phase=2*np.pi*(82*hit-38*hit*hit)
        envelope=np.minimum(hit*100,1)*np.exp(-hit*8.5)
        signal=(np.sin(phase)+.4*np.sin(phase*2.07)+soft*1.3)*(1+.18*np.sin(hit*160))*envelope
    else:
        phase=2*np.pi*(82*t-35*t*t)
        signal=(np.sin(phase)+soft*2)*np.exp(-p*4)*np.sin(np.pi*p)**.4
    signal=np.tanh(signal*1.3)
    signal*=.48/max(float(np.abs(signal).max()),1e-9)
    signal*=np.minimum((1-p)*40,1)
    with wave.open(str(ROOT/f'listener_{kind}.wav'),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes((signal*32767).astype('<i2').tobytes())
print('Listener: four spatial creature cues')
