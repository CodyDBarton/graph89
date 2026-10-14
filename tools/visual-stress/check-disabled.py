#!/usr/bin/env python3
"""Check exported A_SHADED identities against actual ROM pixels, not guesses."""
from pathlib import Path
import argparse,json,collections
p=argparse.ArgumentParser();p.add_argument('captures',type=Path);p.add_argument('--original',type=Path);a=p.parse_args()
fonts=(a.captures/'fonts.bin').read_bytes();counts=collections.Counter();frames=0
for f in sorted(a.captures.glob('*.pgm')):
    pixels=f.read_bytes().split(b'\n',3)[3]
    if a.original:
        old=a.original/f.name
        assert old.exists() and old.read_bytes()==f.read_bytes(),('Original LCD changed',f.name)
    for c in json.loads(f.with_suffix('.cells.json').read_text()):
        x,y,font,code,inverse,w,h,attr,l,t,r,b=c
        if font not in range(3) or attr!=3:continue
        template=fonts[(font*256+code)*12:][:12]
        assert (w,h)==tuple(template[:2]),(f,c)
        first=max(0,t-y)
        # Native validation permits a solid live cursor in blank padding.
        ink=[(dx,dy) for dy in range(h) for dx in range(w) if template[2+dy]>>(7-dx)&1]
        left=min(dx for dx,dy in ink);right=max(dx for dx,dy in ink)
        top=min(dy for dx,dy in ink);bottom=max(dy for dx,dy in ink)
        for dy in range(h):
            mask=0x5a if (dy-first)&1 else 0xa5
            for dx in range(w):
                xx,yy=x+dx,y+dy
                if not(l<=xx<r and t<=yy<b):continue
                expected=bool((template[2+dy]>>(7-dx)&1) and (mask>>(7-(xx&7))&1)) ^ bool(inverse)
                if (pixels[yy*160+xx]==30)==expected:continue
                cursor=(dx<left or dx>right) and all((pixels[(y+j)*160+xx]==30)!=bool(inverse) for j in range(h) if t<=y+j<b)
                underline=dy==h-1 and dy>bottom and all((pixels[yy*160+x+j]==30)!=bool(inverse) for j in range(w) if l<=x+j<r)
                assert cursor or underline,('Shaded identity mismatch',f.name,c,dx,dy)
        counts[font]+=1
    frames+=1
assert sum(counts.values())>100,counts
print(f'{frames} actual-ROM frames; {sum(counts.values())} validated disabled glyph cells; font counts {dict(counts)}.')
if a.original:print('All original LCD frames remain byte-identical.')
