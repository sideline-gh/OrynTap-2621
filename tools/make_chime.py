#!/usr/bin/env python3
"""OrynTap: synthesise the Pomodoro chime (our own sound, no licence needed).
Two soft bell tones, 1.2 s, 44.1 kHz mono 16-bit -> media-src/chime.wav
Then: ffmpeg -i media-src/chime.wav -c:a libmp3lame -b:a 64k assets/media/chime.mp3"""
import numpy as np, wave
from pathlib import Path
SR, DUR = 44100, 1.2
t = np.arange(int(SR * DUR)) / SR
def bell(f, start, dur=0.9):
    x = np.zeros_like(t); m = (t >= start) & (t < start + dur); tt = t[m] - start
    env = np.exp(-tt * 5.5) * np.minimum(1, tt / 0.008)            # 8 ms attack, soft decay
    x[m] = env * (np.sin(2*np.pi*f*tt) + 0.35*np.sin(2*np.pi*2*f*tt) + 0.12*np.sin(2*np.pi*3.01*f*tt))
    return x
y = bell(880.0, 0.0) + bell(1318.5, 0.22)                           # A5 then E6
y = 0.55 * y / np.abs(y).max()                                      # peak about -5 dBFS, not loud
pcm = (y * 32767).astype("<i2")
out = Path(__file__).resolve().parent.parent / "media-src" / "chime.wav"
with wave.open(str(out), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print(out, out.stat().st_size, "bytes")
