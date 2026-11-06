#!/usr/bin/env python3
"""Quiet synthesized corvid placeholders: raspy crow caws and lower raven croaks (numpy + stdlib).
No recordings or external samples. Re-run to replace the four WAV assets deterministically.
"""
from pathlib import Path
import wave
import numpy as np
ROOT=Path(__file__).resolve().parent.parent/'assets/audio/wildlife'
ROOT.mkdir(parents=True,exist_ok=True)
RATE=22050
for species,base,duration,formants in [('crow',235.,.38,[700,1400,2300]),('raven',125.,.56,[350,700,1300])]:
 for variant in range(2):
  rng=np.random.default_rng(27+variant);t=np.arange(int(RATE*duration*(1-.18*variant)))/RATE
  u=t/t[-1];jitter=np.interp(t,np.linspace(0,t[-1],24),rng.normal(0,7,len(np.linspace(0,t[-1],24))))
  f=base*(1+.13*np.sin(u*np.pi)-.17*u)+jitter
  phase=np.cumsum(f)*2*np.pi/RATE
  voice=np.zeros_like(t)
  for h in range(1,23):
   weight=.06/h+sum(np.exp(-.5*((h*base-fm)/(fm*.19))**2) for fm in formants)/(1+h*.2)
   voice+=weight*np.sin(phase*h+.2*np.sin(t*57))
  noise=rng.normal(0,1,len(t));noise=np.convolve(noise,[.2,.6,.2],mode='same')
  envelope=np.sin(np.pi*u)**.7*np.minimum(1,u*20)*np.minimum(1,(1-u)*20)
  signal=(voice+.14*noise)*envelope*(.8+.2*np.sin(t*2*np.pi*34))
  pcm=np.int16(signal/(np.max(np.abs(signal))+1e-8)*.58*32767)
  with wave.open(str(ROOT/f'{species}_{variant}.wav'),'wb') as out:
   out.setnchannels(1);out.setsampwidth(2);out.setframerate(RATE);out.writeframes(pcm.tobytes())
print('Wrote four quiet corvid call samples')
