#!/usr/bin/env python3
"""Compare both renderers' retained/fallback merge using locally captured frames."""
from pathlib import Path
import json,subprocess,sys
root=Path(__file__).resolve().parents[2]
frames=Path(sys.argv[1]).resolve();fonts=Path(sys.argv[2]).resolve()
out=root/'build/retained-merge-parity';out.mkdir(parents=True,exist_ok=True)
bases=[]
for p in sorted(frames.glob('*.pgm')):
    pixels=p.read_bytes().split(b'\n',3)[3]
    assert len(pixels)==16000
    base=out/p.stem;bases.append(str(base))
    base.with_suffix('.pixels').write_bytes(bytes(int(b==30) for b in pixels))
    cells=json.loads(p.with_suffix('.cells.json').read_text())
    base.with_suffix('.packets').write_text(' '.join(str(x) for cell in cells for x in cell))
java=Path('/opt/homebrew/opt/openjdk@11/libexec/openjdk.jdk/Contents/Home/bin')
subprocess.run([str(java/'javac'),'-d',str(out),str(root/'app/src/main/java/com/graph89/emulationcore/SharpTextRecognizer.java'),str(root/'android/tests/RetainedTextParity.java')],check=True)
subprocess.run(['xcrun','swiftc','-O',str(root/'ios/App/SharpTextRecognizer.swift'),str(root/'ios/tests/RetainedTextParity.swift'),'-o',str(out/'swift-merge')],check=True)
a=subprocess.check_output([str(java/'java'),'-cp',str(out),'RetainedTextParity',str(fonts),*bases],text=True).splitlines()
b=subprocess.check_output([str(out/'swift-merge'),str(fonts),*bases],text=True).splitlines()
assert a==b,'Android/iOS retained merge mismatch'
assert len(a)==len(bases)>0
print(f'{len(a)} captured frames: retained identities and fallback merge identical on Android/iOS.')

by_name={Path(base).name:row for base,row in zip(bases,a)}
required={
    '15-tall-integral-pretty': [(57789,0,25),(40,0,25),(41,0,25)],
    '15b-tall-integral-selected': [(57789,1,25),(40,1,25),(41,1,25)],
}
for name,wanted in required.items():
    if name not in by_name:continue
    rows=[list(map(int,c.split(','))) for c in by_name[name].split(';') if c]
    for char,inverse,height in wanted:
        assert any(c[3]==char and c[4]==inverse and c[6]==height for c in rows),(name,char,inverse,height)
print('Actual-ROM normal/inverse tall integral and parenthesis checks passed.')

if '16c-catalog-p' in by_name:
    rows=[list(map(int,c.split(','))) for c in by_name['16c-catalog-p'].split(';') if c]
    for x,y in [(23,60),(23,68)]:
        assert any(c[0]==x and c[1]==y and c[3]==57618 for c in rows),('Catalog conversion triangle',x,y)
    print('Actual-ROM P-triangle-Rx and P-triangle-Ry identities passed.')

for name in ['15d-clipped-math-pretty','15e-clipped-math-selected']:
    if name not in by_name: continue
    packets=json.loads((frames/(name+'.cells.json')).read_text())
    rows=[list(map(int,c.split(','))) for c in by_name[name].split(';') if c]
    for code,ch in [(189,57789),(40,40),(41,41)]:
        wanted=[c for c in packets if c[2]==3 and c[3]==code and (c[1]<c[9] or c[1]+c[6]>c[11])]
        if name.endswith('selected'):wanted=[c for c in wanted if c[4]==1]
        assert wanted,('Missing native clipped shape',name,code)
        for c in wanted:
            assert any(r[0]==c[0] and r[1]==c[1] and r[3]==ch and r[4]==c[4] and r[6]==c[6] for r in rows),(name,c)
    if name.endswith('pretty'):
        letters=[c for c in packets if c[2]<3 and 33<=c[3]<127 and c[1]<c[9]]
        assert letters, 'Fixture must include a top-clipped ROM character'
        for c in letters:
            assert any(r[0]==c[0] and r[1]==c[1] and r[3]==c[3] for r in rows),(name,c)
print('Actual-ROM clipped normal/inverse integrals, parentheses and top-edge text passed.')

for name in ['16d-inverse-trig-input','16e-inverse-trig-pretty','16f-inverse-trig-selected']:
    if name not in by_name: continue
    packets=json.loads((frames/(name+'.cells.json')).read_text())
    rows=[list(map(int,c.split(','))) for c in by_name[name].split(';') if c]
    wanted=[c for c in packets if c[3]==180]
    assert wanted, ('Inverse trig fixture must contain ROM character 180',name)
    for c in wanted:
        assert any(r[0]==c[0] and r[1]==c[1] and r[2]==c[2] and r[3]==57780 and r[4]==c[4] for r in rows),(name,c)
print('Actual-ROM inverse trig raised -1 retained in input, pretty print and selected history.')

for prefix in ['18-cursor-end','19-cursor-middle']:
    names=[n for n in by_name if n.startswith(prefix)]
    if not names: continue
    masks=set()
    for name in names:
        packets=json.loads((frames/(name+'.cells.json')).read_text())
        masks.add(next((c[4] for c in packets if c[2]==4),0))
        rows=[list(map(int,c.split(','))) for c in by_name[name].split(';') if c]
        for x,ch in [(1,87),(7,77),(13,49),(19,41)]:
            assert any(r[0]==x and r[1]==85 and r[2]==1 and r[3]==ch and r[4]==0 for r in rows),(name,x,ch)
    assert 0 in masks and 255 in masks, (prefix,masks)
print('Actual-ROM cursor on/off cycles preserve all entry glyphs at end and middle.')
