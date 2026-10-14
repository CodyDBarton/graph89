#!/usr/bin/env python3
"""Actual-ROM LCM error must restore completed compact history, not stale groups."""
from pathlib import Path
import argparse,json,re
p=argparse.ArgumentParser();p.add_argument('captures',type=Path);p.add_argument('--original',type=Path);p.add_argument("--fast",action="store_true");a=p.parse_args()
def settled(root):
 acts=[(int(m[1]),int(m[2]),m[3]) for line in (root/'actions.txt').read_text().splitlines() if (m:=re.match(r'(\d+) (\d+) (\S+)',line))]
 files=sorted(root.glob('*.pgm'));return [(name,files[(acts[i+1][1] if i+1<len(acts) else len(files))-1]) for i,(_,_,name) in enumerate(acts)]
def layout(cells):
 groups={c[3]:(c[6],c[7]) for c in cells if c[2]==5};return sorted(tuple(c[:8]+list(groups[c[8]])+c[9:]) for c in cells if c[2] in (6,7))
# A keyboard/status interrupt must never become a Home equation child.
for f in sorted(a.captures.glob('*.cells.json')):
 cs=json.loads(f.read_text());groups={c[3] for c in cs if c[2]==5 and c[7] in (1,2)}
 assert not any(c[8] in groups and ((c[2]==6 and c[1]>=83) or (c[2]==7 and min(c[1],c[4])>=83)) for c in cs),('Foreign status child',f.name)
if a.fast:
 for name,f in settled(a.captures):
  cs=json.loads(f.with_suffix('.cells.json').read_text())
  if name=='queued-lcm-error':assert not any(c[2]==13 for c in cs)
  if name in ('queued-lcm-dismiss','queued-lcm-clear','queued-lcm-select'):
   assert any(c[2]==13 for c in cs),('Compact history missing',f.name)
   assert len([c for c in cs if c[2]==5])==6,('Three input/answer pairs required',f.name)
 print('Fast queued LCM error: three intact history pairs restored; no status glyph can enlarge a math group.')
 if a.original:
  for (name,f),(other,old) in zip(settled(a.captures),settled(a.original)):
   assert name==other and f.read_bytes()[-16000:][16*160:83*160]==old.read_bytes()[-16000:][16*160:83*160],name
  print('Every fast-sequence settled Home body matches original display.')
 raise SystemExit(0)
reference=None;errors=0;checks=0
for name,f in settled(a.captures):
 cs=json.loads(f.with_suffix('.cells.json').read_text())
 if name=='lcm-error-input':
  assert any(c[2]==13 for c in cs),('Before-error history incomplete',f.name)
  reference=layout(cs);body=f.read_bytes()[-16000:][16*160:83*160]
 if name=='lcm-error-show':
  errors+=1;assert not any(c[2]==13 for c in cs),('Compact history must not cover an error dialog',f.name)
 if name in ('lcm-error-dismiss','lcm-error-clear'):
  assert reference is not None
  assert any(c[2]==13 for c in cs),('Compact history missing after error',f.name)
  assert layout(cs)==reference,('History math changed after error',f.name)
  assert f.read_bytes()[-16000:][16*160:83*160]==body,('History native pixels changed after error',f.name)
  checks+=1
assert errors==5 and checks==10,(errors,checks)
if a.original:
 for (name,f),(other,old) in zip(settled(a.captures),settled(a.original)):
  assert name==other
  assert f.read_bytes()[-16000:][16*160:83*160]==old.read_bytes()[-16000:][16*160:83*160],('Changed native Home body',name)
print(f'{errors} real LCM error dialogs; {checks} dismiss/clear checks: compact layout restored unchanged, never drawn over the dialog.')
if a.original:print('Every settled Home body is byte-identical to the calculator with retained hooks disabled.')
