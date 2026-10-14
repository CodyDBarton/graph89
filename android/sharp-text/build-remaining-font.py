"""Add the sixteen approved symbols; preserve every existing font contour."""
from pathlib import Path
import argparse,math,runpy,sys,tempfile
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.recordingPen import DecomposingRecordingPen,RecordingPen
from PIL import ImageDraw
p=argparse.ArgumentParser();p.add_argument('templates',type=Path);p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
font=TTFont(a.input);before={}
for name in font.getGlyphOrder():
 if name.startswith('approvedRemaining'):continue
 pen=RecordingPen();font.getGlyphSet()[name].draw(pen);before[name]=pen.value
codes=[11,14,15,16,17,19,20,21,23,24,25,26,27,127,173,181]
# Record exactly the approved preview's drawing calls as vector contours.
# Preview coordinates are supersampled by 32 per native unit; font uses 200.
class VectorDraw:
 def __init__(self,real):self.real=real;self.pen=TTGlyphPen(None);self.active=False
 def polygon(self,points,fill=None,**kwargs):
  if not self.active:return self.real.polygon(points,fill=fill,**kwargs)
  pts=list(points);area=sum(x*y1-x1*y for (x,y),(x1,y1) in zip(pts,pts[1:]+pts[:1]));black=fill==(30,)*3
  if (area>0)!=black:pts.reverse()
  pts=[(x*200/32,(10-y/32)*200) for x,y in pts]
  self.pen.moveTo(pts[0]);[self.pen.lineTo(pt) for pt in pts[1:]];self.pen.closePath()
 def rectangle(self,box,fill=None,**kwargs):
  if not self.active:return self.real.rectangle(box,fill=fill,**kwargs)
  x,y,r,b=box;self.polygon([(x,y),(r,y),(r,b),(x,b)],fill=fill)
 def rounded(self,box,radius,fill):
  x,y,r,b=box;rad=min(radius,(r-x)/2,(b-y)/2);points=[]
  for cx,cy,start in [(r-rad,y+rad,-90),(r-rad,b-rad,0),(x+rad,b-rad,90),(x+rad,y+rad,180)]:
   for i in range(9):
    ang=math.radians(start+i*90/8);points.append((cx+rad*math.cos(ang),cy+rad*math.sin(ang)))
  self.polygon(points,fill=fill)
 def rounded_rectangle(self,box,radius=0,fill=None,outline=None,width=1,**kwargs):
  if not self.active:return self.real.rounded_rectangle(box,radius,fill,outline,width,**kwargs)
  self.rounded(box,radius,fill or outline)
  if fill is None:
   x,y,r,b=box;self.rounded((x+width,y+width,r-width,b-width),max(0,radius-width),(210,)*3)
 def line(self,points,fill=None,width=1,joint=None,**kwargs):
  if not self.active:return self.real.line(points,fill,width,joint,**kwargs)
  points=list(points)
  for (x,y),(r,b) in zip(points,points[1:]):
   length=math.hypot(r-x,b-y);nx=-(b-y)/length*width/2;ny=(r-x)/length*width/2
   self.polygon([(x+nx,y+ny),(r+nx,b+ny),(r-nx,b-ny),(x-nx,y-ny)],fill=fill)
  if joint=='curve':
   for x,y in points[1:-1]:self.rounded((x-width/2,y-width/2,x+width/2,y+width/2),width/2,fill)
 def text(self,*args,**kwargs):return self.real.text(*args,**kwargs)
# Execute the existing approved preview with this vector recording backend.
real_draw=ImageDraw.Draw
root=Path(__file__).resolve().parents[2]
records={}
def recording_draw(im,*args,**kwargs):
    draw=VectorDraw(real_draw(im,*args,**kwargs));v=sys._getframe(1).f_locals
    if im is v.get('sharp') and v.get('code') in codes and v.get('f') in range(3):
        draw.active=True;records[(v['f'],v['code'])]=draw
    return draw
ImageDraw.Draw=recording_draw
oldargv=sys.argv;sys.argv=[str(root/'android/sharp-text/preview-remaining-symbols.py'),str(a.templates),'--output',str(root/'build/remaining-symbols')]
try:runpy.run_path(sys.argv[0],run_name='__main__')
finally:sys.argv=oldargv;ImageDraw.Draw=real_draw
rom=a.templates.read_bytes()
italic=TTFont('/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf')
for f in range(3):
 for code in codes:
  name=f'approvedRemaining{f}_{code}';pen=records[f,code].pen
  if code==181:
   t=rom[(f*256+code)*12:][:12];w,h=t[:2];ink=[(x,y) for y in range(h) for x in range(w) if t[2+y]>>(7-x)&1];l=min(x for x,y in ink);r=max(x for x,y in ink)+1;top=min(y for x,y in ink);b=max(y for x,y in ink)+1
   source=italic.getBestCmap()[ord('μ')];g=italic['glyf'][source];g.recalcBounds(italic['glyf']);sx=(r-l)*200/(g.xMax-g.xMin);sy=(b-top)*200/(g.yMax-g.yMin)
   rec=DecomposingRecordingPen(italic.getGlyphSet());italic.getGlyphSet()[source].draw(rec);pen=TTGlyphPen(None);rec.replay(TransformPen(pen,(sx,0,0,sy,l*200-g.xMin*sx,(10-b)*200-g.yMin*sy)))
  glyph=pen.glyph();glyph.recalcBounds(font['glyf'])
  w,h=rom[(f*256+code)*12:][:2]
  assert glyph.numberOfContours>0 and -10<=glyph.xMin and glyph.xMax<=w*200+10 and (10-h)*200-10<=glyph.yMin<=glyph.yMax<=2010,(f,code,'Invalid native-cell outline')
  font['glyf'][name]=glyph;font['hmtx'].metrics[name]=(1600,glyph.xMin)
  for table in font['cmap'].tables:
   if table.isUnicode() and table.format in (4,12):
    table.cmap[0xe400+f*256+code]=name
    if f==1:table.cmap[0xe100+code]=name
font.setGlyphOrder(list(dict.fromkeys(font.getGlyphOrder()+[f'approvedRemaining{f}_{c}' for f in range(3) for c in codes])))
for name,old in before.items():
 pen=RecordingPen();font.getGlyphSet()[name].draw(pen);assert old==pen.value,('Existing outline changed',name)
a.output.parent.mkdir(parents=True,exist_ok=True);font.save(a.output)
print('48 size-specific approved outlines added; every existing outline unchanged.')
