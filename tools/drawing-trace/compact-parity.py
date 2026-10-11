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
# New native captures must identify real Home inputs/results independently of
# their width. Historical fixtures have zero attributes and stay supported.
if any(r[2]==5 and r[7] for r in packets['03-pretty-print']):
    assert [r[7] for r in packets['03-pretty-print'] if r[2]==5]==[1,2]
    assert [r[7] for r in packets['21-compact-long-pretty'] if r[2]==5]==[1,2,1,2,2]
    assert all(r[7]==0 for r in packets['23d-y-editor-next'] if r[2]==5),'Y= must not inherit Home alignment flags'
# Explicitly cross the new, wider viewport; the old edge captures can now
# legitimately remain inside it. Keep these frames immediately after each editor.
for source,name in [('20c-compact-left-edge','20d-compact-new-left-edge'),('23c2-y-editor-left-edge','23c3-y-editor-new-left-edge')]:
    cells=[r[:] for r in packets[source]]
    next(r for r in cells if r[2]==8)[0]=0
    base=out/name;after=bases.index(str(out/source))+1;bases.insert(after,str(base));packets[name]=cells
    base.with_suffix('.packets').write_text(' '.join(str(x) for cell in cells for x in cell))
def fixture(name,cells):
    base=out/name;bases.append(str(base));packets[name]=cells
    base.with_suffix('.packets').write_text(' '.join(str(x) for cell in cells for x in cell))
for name,code in [('90-wide-input',120),('91-narrow-input',105)]:
    fixture(name,[[50,0,8,1816,0,50,0,123456,0,84,160,93]]+[[i,0,9,code,0,0,0,0,0,0,0,0] for i in range(50)])
# Numerator, denominator, exponent and fraction bar share the same x map.
math=[[8,30,6,120,0,6,8,1,42,0,0,0],[18,30,6,43,0,6,8,1,42,0,0,0],
      [18,22,6,50,0,4,5,0,42,0,0,0],[8,45,6,120,0,6,8,1,42,0,0,0],
      [8,41,7,24,41,1,0,0,42,0,0,0]]
for name,inverse in [('92-spaced-fraction',0),('93-spaced-fraction-inverse',1)]:
    fixture(name,[[8,22,5,42,inverse,len(math),0,0,0,0,0,0]]+math)
# An initially right-aligned answer must keep its right edge after tightening.
right_math=[[r[0]+130,r[1],r[2],r[3]+(130 if r[2]==7 else 0),*r[4:]] for r in math]
fixture('94-spaced-right-answer',[[138,22,5,42,0,len(math),0,1,0,0,0,0]]+right_math)
# An answer beginning left of the midpoint must still align right. A native
# answer wider than the screen may fit after compaction; truly wide ones must
# preserve their left edge. Explicit inputs must never be mistaken for answers.
for name,left,width,role,inverse in [('98-medium-answer',50,110,1,0),('98b-newly-fitting-answer',8,180,1,0),
    ('98c-wide-answer',8,240,1,0),('98d-edge-input',50,110,2,0),('98e-inverse-answer',50,110,1,1)]:
    cells=[[left,30,6,120,0,6,8,1,42,0,0,0],[left+width-6,30,6,120,0,6,8,1,42,0,0,0],
           [left,41,7,left+width-1,41,1,0,0,42,0,0,0]]
    if width==240: cells=cells[:2]+[[left+i,30,6,120,0,6,8,1,42,0,0,0] for i in range(6,234,6)]+cells[2:]
    fixture(name,[[0,0,5,42,inverse,len(cells),0,role,0,16,160,83]]+cells)
# Elastic outlines follow the smaller expression; their old raster stems do not
# prevent tightening. Protect all ordinary glyph cells, including descenders.
tall=math+[[0,22,6,189,0,5,31,3,42,0,0,0],[28,22,6,41,0,3,31,3,42,0,0,0],
           [2,24,7,2,50,1,0,0,42,0,0,0]]
fixture('95-vertical-tall',[[0,22,5,42,0,len(tall),0,0,0,0,0,0]]+tall)
y_math=[[r[0]+24,r[1],r[2],r[3]+(24 if r[2]==7 else 0),*r[4:]] for r in math]
fixture('96-vertical-y-baseline',[[0,0,10,0,0,0,0,0,0,0,0,0],[19,36,1,61,0,6,8,0,0,16,160,83],
        [32,22,5,42,0,len(y_math),0,0,0,0,0,0]]+y_math)
diagonal=math+[[0,22,7,28,52,1,0,0,42,0,0,0]]
fixture('97-vertical-diagonal',[[0,22,5,42,0,len(diagonal),0,0,0,0,0,0]]+diagonal)
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
        assert header[4]==n and header[3]<=50 and header[2]+header[3]<=n
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
print(f'{len(list(frames.glob("*.cells.json")))} ROM captures plus {len(a)-len(list(frames.glob("*.cells.json")))} spacing fixtures: Android/iOS compact layout identical. Full input exposes earlier text; originally clipped pretty-print glyphs become visible; full tall math retained.')

for name in ['23b-y-editor','23c-y-editor-input','23d-y-editor-next']:
    assert by_name[name][0][:2]==[1,1], ('Y= list and input must both be compact',name)
    assert any(p[2]==8 and p[6]==1 and p[8]==36 for p in packets[name]), ('Y= input prefix bounds lost',name)
assert by_name['23e-home-return'][0][:2]==[1,1], 'Compact Home must resume after leaving Y='
for end,within,edge in [('20-compact-long-input','20b-compact-left-within','20d-compact-new-left-edge'),('23c-y-editor-input','23c1-y-editor-left-within','23c3-y-editor-new-left-edge')]:
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

wide,narrow=by_name['90-wide-input'],by_name['91-narrow-input']
assert narrow[0][3]>wide[0][3], 'Narrow letters must expose more input at the same font size'
assert all(r[2]==800 for r in narrow[1:]), 'Input font size must remain unchanged'
normal,inverted=by_name['92-spaced-fraction'],by_name['93-spaced-fraction-inverse']
assert [r[:3]+r[4:] for r in normal[1:]]==[r[:3]+r[4:] for r in inverted[1:]], 'Selection must not alter mathematical spacing'
assert all(r[3]==1 for r in inverted[1:]), 'All selected primitives must remain inverted'
assert normal[2][0]==13760, 'Four-unit mathematical gutter must tighten to two without shrinking glyphs'
assert normal[2][0]==normal[3][0], 'Exponent and base must follow the same coordinate map'
assert normal[1][0]==normal[4][0], 'Numerator and denominator alignment must be preserved'
assert normal[5][5]==18080, 'Fraction bar must shorten with its contents'
font_bytes=fonts.read_bytes()
expected=[tuple(font_bytes[(r[7]*256+r[3])*12:(r[7]*256+r[3])*12+2]) for r in math if r[2]==6]
assert [(r[5],r[6]) for r in normal[1:5]]==expected, 'Glyph geometry must stay unchanged'
assert by_name['94-spaced-right-answer'][5][5]==159280, 'Right-aligned expression must reach the right margin'
print('Variable-width input reveals more text without smaller letters. Fractions/exponents tighten together, selection is stable, and right-aligned answers retain their edge.')

for row in narrow[1:]:
    assert abs(row[0]+row[5]*800/2-(row[8]+row[7]/2))<1.1, 'Narrow input glyph must be centered in its actual selection slot'

# The bottom-anchored fraction becomes 4.5 native units shorter, with the same
# text height. Numerator/bar/denominator retain their ordering and clear gaps.
assert normal[3][1]==42320 and normal[1][1]==47000 and normal[5][1]==53840 and normal[4][1]==55640, 'Fraction vertical gaps must tighten predictably'
assert all(r[9]==1000 for r in normal[1:5]), 'Ordinary glyphs and descenders must never be squashed'
assert normal[1][1]+normal[1][6]*720<normal[5][1], 'Numerator must clear the fraction bar'
assert normal[5][1]+720<normal[4][1], 'Denominator must clear the fraction bar'
assert all(r[9]==855 for r in by_name['95-vertical-tall'][1:] if r[4] in [57789,41]), 'Tall outlines must shorten with their enclosed fraction'
assert not any(r[4]==-1 and r[0]==r[5] for r in by_name['95-vertical-tall'][1:]), 'Duplicate tall-delimiter raster stem must remain suppressed'
assert any(r[4]==61 and r[1]==30400 for r in by_name['96-vertical-y-baseline'][1:]), 'Y= row label baseline must remain anchored'
assert by_name['96-vertical-y-baseline'][1][1]==26080, 'Y= expression must remain aligned around its label baseline'
assert by_name['97-vertical-diagonal'][1][1]==44840, 'Diagonal graphic must protect occupied rows from vertical reflow'
for name in ['15d-clipped-math-pretty','15e-clipped-math-selected']:
    assert any(r[4]==57789 and r[9]<1000 for r in by_name[name][1:]), ('Actual nested fraction must shorten its tall integral',name)
print('Vertical fractions/exponents tighten without squashing text. Tall outlines shorten, duplicate stems stay suppressed, Y= baselines remain anchored, and oblique graphics stay protected.')

assert inverted[0][6:8]==[1,19080], 'Inverse background must follow the shortened expression height'
assert normal[0][9]==3240, 'Synthetic fraction must save exactly 4.5 native rows at 72% size'
assert by_name['15d-clipped-math-pretty'][0][8]>0, 'History marker must move together with the shortened integral'

for name in ['98-medium-answer','98b-newly-fitting-answer','98e-inverse-answer']:
    rows=by_name[name]
    assert rows[2][0]+rows[2][5]*rows[2][2]==160000,('Fitting result must reach the right edge',name)
assert by_name['98c-wide-answer'][1][0]==8000,'Oversize output must retain its beginning'
assert by_name['98d-edge-input'][1][0]==38240,'Entered expression must retain its left anchor'
assert by_name['98e-inverse-answer'][1][0]==by_name['98-medium-answer'][1][0],'Selection must not change alignment'
print('Medium, newly fitting, oversize, selected answers and explicit left-aligned inputs passed.')
