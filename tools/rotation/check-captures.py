#!/usr/bin/env python3
"""Compare real-ROM 120 Hz sampled rotation, without touching app state."""
from pathlib import Path
import hashlib
import math
import struct
import sys

def read(path):
    b=path.read_bytes();n,d=struct.unpack("ii",b[:8])
    return struct.unpack(f"{n}f",b[16008:16008+n*4]), struct.unpack(f"{d}f",b[16008+n*4:])
def shapes(folder,phase):
    return [read(f) for f in sorted(folder.glob(f"*{phase}.hdplot"))]
def unique(frames):
    return len({hashlib.sha256(struct.pack(f"{len(p)}f",*p)).digest() for p,d in frames})
before,after=map(Path,sys.argv[1:3])
a=shapes(before,"rotation-auto");b=shapes(after,"rotation-auto")
assert len(a)==len(b)>=240
assert unique(a)<25 and unique(b)>200
for points,deco in b:
    labels=[deco[i+1] for i in range(0,len(deco),4) if math.isnan(deco[i]) and 120<=deco[i+1]<=122]
    assert sorted(labels)==[120,121,122]
for phase in ["rotation-ready","rotation-stopped"]:
    p,_=shapes(before,phase)[-1];q,d=shapes(after,phase)[-1]
    assert len(p)==len(q)
    assert all((math.isnan(x) and math.isnan(y)) or abs(x-y)<0.00002 for x,y in zip(p,q)),phase
stopped=shapes(after,"rotation-stopped")
assert unique(stopped)<=2 # One calculator-owned redraw may finish after ESC.
for p,d in stopped:
    for i in range(0,len(d),4):
        if math.isnan(d[i]) and d[i+1]==-9: assert d[i+2]==0
print(f"PASS: {unique(a)} -> {unique(b)} distinct views in the same two-second 120 Hz sample; exact native start/end projection; axes labeled; ESC stops interpolation")
