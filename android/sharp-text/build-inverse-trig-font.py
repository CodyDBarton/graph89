"""Add approved raised-minus-one variants without changing existing outlines."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
import sys
root=Path(__file__).resolve().parents[2]
if len(sys.argv)!=3: raise SystemExit('Usage: build-inverse-trig-font.py INPUT_TTF OUTPUT_TTF')
font=TTFont(sys.argv[1])
preview=Path(sys.argv[2])
# Ink rectangles from the ROM, in each of its three font sizes. The raised
# minus/one is a single character (180), not two separately drawn characters.
boxes=[((0,1,2,2),(3,0,5,4)),((0,2,2,3),(2,0,5,5)),((1,3,4,4),(4,0,8,6))]
for f,(minus,one) in enumerate(boxes):
    pen=TTGlyphPen(None)
    for char,box in [('-',minus),('1',one)]:
        g=font['glyf'][font.getBestCmap()[ord(char)]];g.recalcBounds(font['glyf'])
        l,t,r,b=box
        # Uniform scaling keeps the approved numeral's curves and serifs.
        scale=min((r-l-.1)/(g.xMax-g.xMin),(b-t-.1)/(g.yMax-g.yMin))
        x=(l+r)/2-(g.xMin+g.xMax)*scale/2
        y=10-(t+b)/2-(g.yMin+g.yMax)*scale/2
        g.draw(TransformPen(pen,(scale*200,0,0,scale*200,x*200,y*200)),font['glyf'])
    name='graph89Inverse'+str(f);font['glyf'][name]=pen.glyph()
    font['hmtx'].metrics[name]=(1600,0)
    font.setGlyphOrder(list(dict.fromkeys(font.getGlyphOrder()+[name])))
    for table in font['cmap'].tables:
        if table.isUnicode() and table.format in (4,12):table.cmap[0xe300+f]=name
for table in font['cmap'].tables:
    if table.isUnicode() and table.format in (4,12):table.cmap[0xe1b4]='graph89Inverse1'
font.save(preview)
