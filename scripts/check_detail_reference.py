#!/usr/bin/env python3
"""V2 detail profile: dependency-free arithmetic and synthetic reference checks.

Not HDL simulation, not a photographic quality or on-board validation.
"""
import json
from pathlib import Path

def gaussian(p):
    return (sum(c*v for c,v in zip((1,2,1,2,4,2,1,2,1),p))+8)>>4

def saturate(v):
    return max(0,min(255,v))

def unsharp(p):
    return saturate(3*p[4] - 2*gaussian(p))

def sobel(p):
    gx=-p[0]+p[2]-2*p[3]+2*p[5]-p[6]+p[8]
    gy=-p[0]-2*p[1]-p[2]+p[6]+2*p[7]+p[8]
    return abs(gx)+abs(gy)

# Exhaust all possible center / mean pairs as a 12-bit signed arithmetic guard.
for c in range(256):
    for g in range(256):
        q=3*c - 2*g
        assert -510 <= q <= 765
        assert 0 <= saturate(q) <= 255
        # Signed twelve-bit range: -2048 through 2047.
        assert -2048 <= q <= 2047

# Bilateral weak-contrast ridges (top/bottom, left/right, diagonals).
N=36
im=[[144 + ((y+x)//14)%4 for x in range(N)] for y in range(N)]
for y in range(4,N-4):
    for x in range(4,N-4):
        if x in (9,10,24,25) or y in (8,9,25,26) or abs(x-y)==1:
            im[y][x]-=7
raw=[[0]*N for _ in range(N)]
sharp=[[0]*N for _ in range(N)]
for y in range(1,N-1):
    for x in range(1,N-1):
        window=[im[yy][xx] for yy in range(y-1,y+2) for xx in range(x-1,x+2)]
        sharp[y][x]=unsharp(window)
        raw[y][x]=im[y][x]
counts={}
for label,field,t in [('previous',raw,64),('v2',sharp,40)]:
    n=0
    for y in range(2,N-2):
        for x in range(2,N-2):
            p=[field[yy][xx] for yy in range(y-1,y+2) for xx in range(x-1,x+2)]
            n+=sobel(p)>=t
    counts[label]=n
assert counts['v2']>counts['previous'],counts
report={
    'test':'python_reference_detail_enhancement',
    'status':'PASS',
    'math_pairs_exhausted':65536,
    'soft_ridge_pixels_above_threshold':counts,
    'scope':'Python mathematical model ONLY; no RTL, synthesis, real video or board verification'
}
root=Path(__file__).resolve().parents[1]
(root/'reports/detail_reference_v2.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
