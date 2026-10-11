#!/usr/bin/env python3
"""Check full-content layout parity and prove previously clipped content is revealed.
Usage: compact-parity.py RETAINED_RUN_DIRECTORY PRIVATE_FONT_TEMPLATES
Fixtures and firmware stay in ignored build output.
"""
from pathlib import Path
import json,subprocess,sys
root=Path(__file__).resolve().parents[2]
frames=Path(sys.argv[1]).resolve();fonts=Path(sys.argv[2]).resolve()
out=root/'build/compact-layout-parity';out.mkdir(parents=True,exist_ok=True)
bases=[];packets={}
for p in sorted(frames.glob('*.cells.json')):
    base=out/p.name.removesuffix('.cells.json');bases.append(str(base))
    cells=json.loads(p.read_text());packets[base.name]=cells
    base.with_suffix('.packets').write_text(' '.join(str(x) for cell in cells for x in cell))
java=Path('/opt/homebrew/opt/openjdk@11/libexec/openjdk.jdk/Contents/Home/bin')
subprocess.run([str(java/'javac'),'-d',str(out),str(root/'app/src/main/java/com/graph89/emulationcore/SharpTextRecognizer.java'),str(root/'android/tests/CompactLayoutParity.java')],check=True)
subprocess.run(['xcrun','swiftc','-O',str(root/'ios/App/SharpTextRecognizer.swift'),str(root/'ios/tests/CompactLayoutParity.swift'),'-o',str(out/'swift-compact')],check=True)
a=subprocess.check_output([str(java/'java'),'-cp',str(out),'CompactLayoutParity',str(fonts),*bases],text=True).splitlines()
b=subprocess.check_output([str(out/'swift-compact'),str(fonts),*bases],text=True).splitlines()
assert a==b,'Compact Android/iOS layout mismatch'
assert len(a)==len(bases)>0
by_name={Path(base).name:[[int(v) for v in item.split(',')] for item in row.split(';')] for base,row in zip(bases,a)}
for name,rows in by_name.items():
    header=rows[0]
    if not any(p[2] in (5,8) for p in packets[name]):assert header[:2]==[0,0],('Non-Home layout must stay original',name)
    if header[1]:
        n=next(p[5] for p in packets[name] if p[2]==8)
        assert header[4]==n and header[3]<=35 and header[2]+header[3]<=n
        if header[5]>=0:assert 0<=header[5]<=159000,('Cursor outside input viewport',name)
name='20-compact-long-input';rows=by_name[name];header=rows[0]
assert header[1]==1 and header[4]>40 and header[3]>=34
native_start=next(p[1] for p in packets[name] if p[2]==8)
assert header[2]<native_start, 'Compact must expose text outside the original editor viewport'
name='21-compact-long-pretty';rows=by_name[name]
assert rows[0][0]==1
hidden=[p for p in packets[name] if p[2]==6 and p[0]>=160]
assert hidden,'Need genuinely clipped expression content'
assert any(160<=p[0]<219 for p in hidden)
assert any(r[2]==720 and 117440<=r[0]<160000 and r[4]>0 for r in rows[1:]),'Originally clipped glyphs must move into view'
if '23-compact-history-edit' in by_name:
    rows=by_name['23-compact-history-edit']
    assert rows[0][0]==1 and rows[0][1]==1, 'Editing input must preserve compact history capture'
if '24-compact-overflow' in by_name:
    assert by_name['24-compact-overflow'][0][0]==0, 'Oversize capture must preserve the original body, including smaller neighbouring results'
for name in ['15d-clipped-math-pretty','15e-clipped-math-selected']:
    rows=by_name[name]
    assert any(r[2]==720 and r[4]==57789 and r[6]>=70 for r in rows[1:]),('Full tall integral lost',name)
    shapes=[p for p in packets[name] if p[2]==6 and p[7]==3]
    raw_stems=[p for p in packets[name] if p[2]==7 and p[0]==p[3] and any(g[0]<=p[0]<g[0]+g[5] and g[1]<=min(p[1],p[4]) and max(p[1],p[4])<g[1]+g[6] for g in shapes)]
    assert len([p for p in raw_stems if p[1]!=p[4]])==3, 'Fixture must include all three duplicate raster stems'
    # This fixture has no legitimate vertical fraction/radical bars.
    assert not any(r[4]==-1 and r[0]==r[5] for r in rows[1:]),('Duplicate delimiter stem leaked into compact view',name)
print(f'{len(a)} ROM captures: Android/iOS compact layout identical. Full input exposes earlier text; originally clipped pretty-print glyphs become visible; full tall math retained.')

for name in ['23b-y-editor','23c-y-editor-input','23d-y-editor-next']:
    assert by_name[name][0][:2]==[1,1], ('Y= list and input must both be compact',name)
    assert any(p[2]==8 and p[6]==1 and p[8]==36 for p in packets[name]), ('Y= input prefix bounds lost',name)
assert by_name['23e-home-return'][0][:2]==[1,1], 'Compact Home must resume after leaving Y='
for end,within,edge in [('20-compact-long-input','20b-compact-left-within','20c-compact-left-edge'),('23c-y-editor-input','23c1-y-editor-left-within','23c2-y-editor-left-edge')]:
    assert by_name[end][0][2]==by_name[within][0][2], ('Viewport moved before cursor reached edge',within)
    assert by_name[within][0][5]<by_name[end][0][5], ('Caret must move within fixed viewport',within)
    assert by_name[edge][0][2]<by_name[within][0][2], ('Viewport must move when cursor crosses left edge',edge)
    assert by_name[edge][0][5] in (1000,27000), ('Cursor must stay at left edge while scrolling',edge)
assert by_name['23c-y-editor-input'][0][3]>=28, 'Y= compact input must fit more than the ROM viewport'
assert any(p[2]==6 and p[0]>=160 for p in packets['23d-y-editor-next']), 'Y= must retain previously clipped pretty-print content'
print('Home/Y= cursor motion keeps viewport fixed until an edge; Y= list, input prefix and full pretty print are compact.')

for name in ["23d1-graph","23d2-window"]:
    assert not any(p[2] in (5,6,7,8,9,10) for p in packets[name]), ("Graph and Window must retain original layout",name)

for name in ['23b-y-editor','23d0-y-extra-equation','23d00-y-extra-scrolled']:
    assert any(p[2]==11 and p[1]>=87 for p in packets[name]), ('Extra Y= rows not captured',name)
    assert any(r[2]==720 and r[4]>=32 and 70000<=r[1]<83000 for r in by_name[name][1:]), ('Extra Y= rows must fill bottom of compact viewport',name)
assert any(p[2]==6 and p[3]==120 and p[1]>=83 for p in packets['23d0-y-extra-equation']), 'Populated hidden y9 must include its real x expression'
print('Y= captures additional real rows and populated offscreen equations, including after scrolling.')

assert not any(r[2]==720 and r[4] in (40,41,77,65,73,78,82,68,70,85,67) for r in by_name['23b-y-editor'][1:]), 'Empty Y= list must not compact input prefix or status text into its body'
