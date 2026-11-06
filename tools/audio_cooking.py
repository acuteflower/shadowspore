"""Quiet cooking foley in the same handmade audio family as the hut and intro."""
import wave
from pathlib import Path
import numpy as np
RATE=22050
OUT=Path(__file__).resolve().parents[1]/'assets/audio/cooking'
OUT.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(8104)
def save(name,sound,loop=False):
    sound=np.clip(sound,-.95,.95)
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE)
        f.writeframes((sound*32767).astype('<i2').tobytes())
def noise(n):
    white=rng.normal(0,1,n)
    return np.convolve(white,np.ones(9)/9,mode='same')
def drops(seconds,count):
    out=np.zeros(int(seconds*RATE))
    for _ in range(count):
        start=int(rng.uniform(0,seconds-.09)*RATE)
        t=np.arange(int(.08*RATE))/RATE
        tone=np.sin(2*np.pi*(rng.uniform(220,500)*t-800*t*t))*np.exp(-t*55)
        out[start:start+len(t)] += tone*rng.uniform(.025,.06)
    return out
n=RATE*3;t=np.arange(n)/RATE
s=noise(n)*.07+drops(3,27)
s *= .6+.4*np.sin(np.pi*t/3)**2
save('simmer',s)
t=np.arange(int(.8*RATE))/RATE
save('sizzle',noise(len(t))*.18*np.sin(np.pi*t/.8)**.6)
s=noise(RATE)*.11*np.sin(np.pi*np.arange(RATE)/RATE)+drops(1,12)
save('pour',s)
t=np.arange(int(.23*RATE))/RATE
save('spoon',(np.sin(2*np.pi*480*t)*.15+noise(len(t))*.07)*np.exp(-t*30))
t=np.arange(int(1.0*RATE))/RATE
save('finish',sum(np.sin(2*np.pi*f*t)*np.exp(-t*4)*.055 for f in [330,440,660]))
print('COOKING AUDIO: five quiet foley clips')
