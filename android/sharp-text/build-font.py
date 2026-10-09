from pathlib import Path
from copy import deepcopy
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.ttProgram import Program
import sys
if len(sys.argv) != 3:
    raise SystemExit('Usage: python build-font.py INPUT_TTF OUTPUT_TTF')
font_input, font_output = map(Path, sys.argv[1:])
font_output.parent.mkdir(parents=True, exist_ok=True)
f=TTFont(font_input);cmap=f.getBestCmap();changed=[]
def pen():return TTGlyphPen(None)
def polygon(p,points):
 p.moveTo(points[0])
 for pt in points[1:]:p.lineTo(pt)
 p.closePath()
def rounded_polygon(p,points):
 # Bracket inside serif joins more broadly than outside terminal corners.
 from math import hypot
 corners=[]
 for i,(x,y) in enumerate(points):
  ax,ay=points[i-1];bx,by=points[(i+1)%len(points)]
  before=hypot(ax-x,ay-y);after=hypot(bx-x,by-y)
  cross=(x-ax)*(by-y)-(y-ay)*(bx-x)
  radius=min(80 if cross>0 else 50,before/2,after/2)
  entry=(x+(ax-x)*radius/before,y+(ay-y)*radius/before)
  exit=(x+(bx-x)*radius/after,y+(by-y)*radius/after)
  corners.append((entry,(x,y),exit))
 p.moveTo(corners[0][0])
 for i,(entry,control,exit) in enumerate(corners):
  if i:p.lineTo(entry)
  p.qCurveTo(control,exit)
 p.closePath()
def put(c,p):
 g=p.glyph();g.program=Program();g.program.fromBytecode(b'');f['glyf'][cmap[ord(c)]]=g;changed.append(c)
# Keep stroke widths, add lower serifs, and shorten the upper-left flags.
p=pen();polygon(p,[(758,1241),(557,1241),(557,1466),(758,1466)])
rounded_polygon(p,[(927,0),(388,0),(388,139),(567,139),(567,922),(386,922),(386,1061),(748,1061),(748,139),(927,139)]);put('i',p)
p=pen();rounded_polygon(p,[(913,0),(373,0),(373,139),(553,139),(553,1327),(373,1327),(373,1466),(733,1466),(733,139),(913,139)]);put('l',p)
# Match the other softened serifs: radius 50 at terminals, 80 at stem joins.
p=pen();p.moveTo((950,0));p.lineTo((316,0));p.qCurveTo((266,0),(266,50))
p.lineTo((266,124));p.qCurveTo((266,174),(316,174));p.lineTo((508,174))
p.qCurveTo((588,174),(588,254));p.lineTo((588,1030));p.lineTo((371,1030))
# A slightly taller vertical tip and a more pronounced upper quadratic arc.
p.lineTo((371,1140));p.qCurveTo((580,1245),(651,1473));p.lineTo((768,1473))
p.lineTo((768,254));p.qCurveTo((768,174),(848,174));p.lineTo((950,174))
p.qCurveTo((1000,174),(1000,124));p.lineTo((1000,50));p.qCurveTo((1000,0),(950,0));p.closePath();put('1',p)
# A smooth oval, counter-wound inner contour, and the ROM's central dot.
p=pen();p.moveTo((614,1473));p.qCurveTo((1092,1473),(1092,723));p.qCurveTo((1092,-25),(614,-25));p.qCurveTo((137,-25),(137,723));p.qCurveTo((137,1473),(614,1473));p.closePath()
p.moveTo((614,1325));p.qCurveTo((322,1325),(322,723));p.qCurveTo((322,123),(614,123));p.qCurveTo((907,123),(907,723));p.qCurveTo((907,1325),(614,1325));p.closePath();polygon(p,[(524,633),(524,813),(704,813),(704,633)]);put('0',p)
# The ROM three starts with a flat bar and diagonal, rather than an upper bowl.
p=pen();p.moveTo((160,1466));p.lineTo((1070,1466));p.lineTo((1070,1292));p.lineTo((685,900));p.qCurveTo((1100,900),(1100,500));p.qCurveTo((1100,-25),(620,-25));p.qCurveTo((150,-25),(135,385));p.lineTo((324,399));p.qCurveTo((360,123),(615,123));p.qCurveTo((913,123),(913,480));p.qCurveTo((913,800),(510,800));p.lineTo((510,956));p.lineTo((840,1292));p.lineTo((160,1292));p.closePath();put('3',p)
# Keep the original TI92Pluspc seven; the straightened study was rejected.
# The bitmap A has a rounded crown rather than the outline font's pointed apex.
p=pen();p.moveTo((140,0));p.lineTo((140,1000));p.qCurveTo((140,1466),(614,1466));p.qCurveTo((1089,1466),(1089,1000));p.lineTo((1089,0));p.lineTo((900,0));p.lineTo((900,650));p.lineTo((330,650));p.lineTo((330,0));p.closePath()
p.moveTo((330,820));p.lineTo((900,820));p.lineTo((900,1000));p.qCurveTo((900,1292),(614,1292));p.qCurveTo((330,1292),(330,1000));p.closePath();put('A',p)
# Square off the t's ascender, and shorten its right crossbar to the ROM shape.
g=f['glyf'][cmap[ord('t')]]
for k,(x,y) in enumerate(g.coordinates):
 if (x,y)==(403,1325):g.coordinates[k]=(403,1434)
 elif x==958:g.coordinates[k]=(800,y)
g.program=Program();g.program.fromBytecode(b'');changed.append('t')
# Soften j's shortened upper flag, preserving its original dot and descender.
p=pen();polygon(p,[(772,1241),(571,1241),(571,1466),(772,1466)])
p.moveTo((762,-113));p.qCurveTo((762,-205),(683,-350),(529,-428),(418,-428))
p.qCurveTo((277,-428),(131,-399));p.lineTo((158,-252))
p.qCurveTo((276,-272),(403,-272));p.qCurveTo((496,-272),(582,-187),(582,-94))
p.lineTo((582,842));p.qCurveTo((582,922),(502,922));p.lineTo((452,922))
p.qCurveTo((402,922),(402,972));p.lineTo((402,1011))
p.qCurveTo((402,1061),(452,1061));p.lineTo((712,1061))
p.qCurveTo((762,1061),(762,1011));p.lineTo((762,-113));p.closePath();put('j',p)
# Keep the edited i/l stems at their original horizontal origin after the
# narrower serifs change xMin. Advances and character spacing stay unchanged.
for c in 'il':
 g=f['glyf'][cmap[ord(c)]];g.recalcBounds(f['glyf'])
 advance,_=f['hmtx'][cmap[ord(c)]];f['hmtx'][cmap[ord(c)]]=(advance,g.xMin)
# Preserve the original descender curves and depths without compression.
for n in f['name'].names:
 if n.nameID in (1,3,4,6):
  value={1:'Graph89 Font Study',3:'Graph89PrivateStudy-1',4:'Graph89 Font Study Regular',6:'Graph89FontStudy-Regular'}[n.nameID]
  n.string=value.encode(n.getEncoding(),errors='replace')
f.save(font_output)
# Round-trip check the edited outlines and glyph coverage.
check=TTFont(font_output);check.ensureDecompiled()
assert check.getBestCmap()==cmap
for c in changed:
 g=check['glyf'][cmap[ord(c)]];assert g.numberOfContours>0
assert check['glyf'][cmap[ord('0')]].numberOfContours==3
assert check['hmtx'].metrics==f['hmtx'].metrics
print('Adjusted:',', '.join(changed),'— font reload, outlines, zero dot, character map and advances checked.')
