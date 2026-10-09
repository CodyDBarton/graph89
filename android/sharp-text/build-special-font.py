from pathlib import Path
import re,json,unicodedata
from fontTools.ttLib import TTFont
import sys
if len(sys.argv) != 3:
    raise SystemExit('Usage: python build-special-font.py APPROVED_V8_TTF OUTPUT_TTF')
font_input, font_output = map(Path, sys.argv[1:])
f=TTFont(font_input);cmap=f.getBestCmap()
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
# Preview v2 changes only imaginary i and infinity.
p=TTGlyphPen(None)
p.moveTo((390,1061));p.lineTo((690,1061));p.lineTo((690,310))
p.qCurveTo((690,165),(790,200));p.lineTo((865,250));p.lineTo((920,140))
p.qCurveTo((800,-10),(640,-10));p.qCurveTo((390,-10),(390,200))
p.lineTo((390,922));p.lineTo((205,922));p.lineTo((205,1061));p.closePath()
p.moveTo((415,1241));p.lineTo((755,1241));p.lineTo((755,1466));p.lineTo((415,1466));p.closePath()
f['glyf']['proposalItalicI']=p.glyph();f['hmtx'].metrics['proposalItalicI']=(1229,205)
# Keep the original smaller left loop and mirror it for the right loop.
# The two loop outlines and counters are therefore exact reflections.
original=f['glyf']['infinity'];original.expand(f['glyf'])
p=TTGlyphPen(None)
p.moveTo((569,811));p.qCurveTo((436,983),(281,983))
p.qCurveTo((179,983),(35,829),(35,717))
p.qCurveTo((35,601),(180,449),(281,449));p.qCurveTo((437,449),(569,621))
p.qCurveTo((701,449),(857,449));p.qCurveTo((958,449),(1103,601),(1103,717))
p.qCurveTo((1103,829),(959,983),(857,983));p.qCurveTo((702,983),(569,811));p.closePath()
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphCoordinates
from fontTools.pens.reverseContourPen import ReverseContourPen
hole=Glyph();hole.numberOfContours=1
lo=original.endPtsOfContours[1]+1;hi=original.endPtsOfContours[2]+1
hole.coordinates=GlyphCoordinates(original.coordinates[lo:hi]);hole.flags=original.flags[lo:hi];hole.endPtsOfContours=[hi-lo-1]
hole.draw(ReverseContourPen(p),f['glyf'])
hole.draw(TransformPen(p,(-1,0,0,1,1138,0)),f['glyf'])
f['glyf']['infinity']=p.glyph()
f.setGlyphOrder(list(dict.fromkeys(f.getGlyphOrder()+['proposalItalicI'])));names=set(f.getGlyphOrder())
# Preview-only Times New Roman candidates for the four requested Greeks.
# Decompose components and scale uniformly; do not alter other glyphs.
from fontTools.pens.recordingPen import DecomposingRecordingPen
roman=TTFont('/System/Library/Fonts/Supplemental/Times New Roman.ttf')
italic=TTFont('/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf')
for name,ch,source,factor,shift in [
    ('Gamma','Γ',roman,1466/1356,0),
    ('gamma','γ',italic,1.08,48),
    ('delta','δ',italic,1466/1422,0),
    ('lambda','λ',italic,1466/1422,0),
    ('alpha','α',italic,1061/905,0)]:
    sourceName=source.getBestCmap()[ord(ch)];gs=source.getGlyphSet()
    recording=DecomposingRecordingPen(gs);gs[sourceName].draw(recording)
    pen=TTGlyphPen(None);recording.replay(TransformPen(pen,(factor,0,0,factor,0,shift)))
    g=pen.glyph();g.recalcBounds(f['glyf'])
    # Center the visible shape in the existing monospaced advance.
    dx=(1229-g.xMax-g.xMin)/2
    pen=TTGlyphPen(None);recording.replay(TransformPen(pen,(factor,0,0,factor,dx,shift)))
    f['glyf'][name]=pen.glyph();f['hmtx'].metrics[name]=(1229,round(g.xMin+dx))
# Angle lambda's descending stroke, preserving the terminal curls.
# Shearing the complete outline also keeps its junction and stroke joins smooth.
g=f['glyf']['lambda']
for i,(x,y) in enumerate(g.coordinates):g.coordinates[i]=(round(x+.32*(1000-y)),y)
g.recalcBounds(f['glyf']);dx=round((1229-g.xMax-g.xMin)/2)
for i,(x,y) in enumerate(g.coordinates):g.coordinates[i]=(x+dx,y)
g.recalcBounds(f['glyf']);f['hmtx'].metrics['lambda']=(1229,g.xMin)
manifest=Path(__file__).with_name('approved-specials.json')
for entry in json.loads(manifest.read_text()):
    if entry['approval'] != 'approved': raise ValueError('Unapproved special glyph')
    for table in f['cmap'].tables:
        if table.isUnicode() and table.format in (4,12):
            table.cmap[entry['preview']] = entry['glyph']
# Preserve source attribution for the Times-derived Greek contours as well as
# the existing TI92Pluspc metadata. The font remains a separate licensed asset.
source_copyright=roman['name'].getDebugName(0)
for record in f['name'].names:
    if record.nameID == 0:
        text=record.toUnicode()
        if source_copyright and source_copyright not in text:
            record.string=(text+'; Greek outlines: '+source_copyright).encode(record.getEncoding())
font_output.parent.mkdir(parents=True,exist_ok=True)
f.save(font_output)
print('Built %d approved special outlines; ASCII outlines unchanged.' % len(json.loads(manifest.read_text())))
