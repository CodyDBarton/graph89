"""Preview only: missing ROM symbols; does not modify the app font or mappings."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import argparse
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('templates',type=Path);p.add_argument('--output',type=Path,default=root/'build/remaining-symbols');a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
rom=a.templates.read_bytes();assert len(rom)==9216
items=[(11,'Return arrow'),(14,'Locked marker'),(15,'Check mark'),(16,'Square marker'),(17,'Left triangle'),(19,'Up triangle'),(20,'Down triangle'),(21,'Left arrow'),(23,'Up arrow'),(24,'Down arrow'),(25,'Large left triangle'),(26,'Large right triangle'),(27,'Shift marker'),(127,'Diamond marker'),(173,'Raised minus'),(181,'Mu')]
label=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',20)
small=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',16)
Z=8;SS=4
for page in range(2):
 im=Image.new('RGB',(1180,1090),'#fafaf7');d=ImageDraw.Draw(im)
 d.text((24,16),'Remaining symbols — proposals only',fill='#222',font=label)
 d.text((24,48),'Original pixels / proposed sharp, at all three ROM sizes. App font unchanged.',fill='#555',font=small)
 for f,title in enumerate(['Small','Medium','Large']):d.text((255+f*305,85),title+'   pixels → sharp',fill='#222',font=small)
 for i,(code,title) in enumerate(items[page*8:page*8+8]):
  y=120+i*118;d.text((24,y+24),title,fill='#222',font=small);d.text((24,y+49),'ROM '+str(code),fill='#777',font=small)
  for f in range(3):
   t=rom[(f*256+code)*12:][:12];w,h=t[:2];ink=[(x,yy) for yy in range(h) for x in range(w) if t[yy+2]>>(7-x)&1]
   if not ink:continue
   l=min(x for x,yy in ink);r=max(x for x,yy in ink)+1;top=min(yy for x,yy in ink);b=max(yy for x,yy in ink)+1
   original=Image.new('RGB',(w*Z,h*Z),(210,)*3);od=ImageDraw.Draw(original)
   for x,yy in ink:od.rectangle((x*Z,yy*Z,(x+1)*Z-1,(yy+1)*Z-1),fill=(30,)*3)
   sharp=Image.new('RGB',(w*Z*SS,h*Z*SS),(210,)*3);sd=ImageDraw.Draw(sharp);color=(30,)*3
   # Proposed shapes use the original ink rectangle, not its padding.
   def pt(x,yy):return ((l+x*(r-l))*Z*SS,(top+yy*(b-top))*Z*SS)
   def line(points,width=.18):sd.line([pt(*v) for v in points],fill=color,width=max(1,round(min(r-l,b-top)*Z*SS*width)),joint='curve')
   def poly(points):sd.polygon([pt(*v) for v in points],fill=color)
   if code in [17,25]:poly([(0,.5),(1,0),(1,1)])
   elif code==26:poly([(0,0),(1,.5),(0,1)])
   elif code==19:poly([(0,1),(.5,0),(1,1)])
   elif code==20:poly([(0,0),(.5,1),(1,0)])
   elif code==16:poly([(0,0),(1,0),(1,1),(0,1)])
   elif code==127:poly([(0,.5),(.5,0),(1,.5),(.5,1)])
   elif code==27:poly([(0,.5),(.5,0),(1,.5),(.68,.5),(.68,1),(.32,1),(.32,.5)])
   elif code==15:line([(.10,.55),(.36,.89),(.91,.09)],.19)
   elif code in [21,23,24]:
    points=[[(.93,.5),(.1,.5)],[(.43,.12),(.08,.5),(.43,.88)]]
    def rotate(p):
     x,yy=p
     return (1-yy,x) if code==23 else (yy,1-x) if code==24 else p
    for v in points:line([rotate(p) for p in v],.16)
   elif code==14:
    sd.rounded_rectangle((*pt(.05,.34),*pt(.95,1)),radius=Z*SS*.22,fill=color)
    sd.rounded_rectangle((*pt(.2,.03),*pt(.8,.6)),radius=Z*SS*.24,outline=color,width=round(Z*SS*.24))
    sd.rectangle((*pt(.44,.64),*pt(.56,.87)),fill=(210,)*3)
   elif code==11:
    # An outlined upright arrow joined to a hollow rectangular return foot.
    # Preserve both counters; the previous open diagonal hook lost this identity.
    poly([(0,.60),(.43,.60),(.43,.34),(.30,.34),(.65,.02),
          (.98,.34),(.85,.34),(.85,.76),(.70,.92),(.57,.98),(0,.98)])
    sd.polygon([pt(*v) for v in [(.56,.29),(.65,.18),(.75,.29),
               (.72,.29),(.72,.70),(.65,.77),(.56,.77)]],fill=(210,)*3)
    sd.rectangle((*pt(.15,.74),*pt(.43,.85)),fill=(210,)*3)
   elif code==173:
    # Keep the raised native position with a lightly softened bar.
    sd.rounded_rectangle((*pt(.04,.12),*pt(.96,.88)),radius=.08*Z*SS,fill=color)
   elif code==181:
    face=ImageFont.truetype('/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf',150);box=face.getbbox('μ');tile=Image.new('RGB',(box[2]-box[0],box[3]-box[1]),(210,)*3);ImageDraw.Draw(tile).text((-box[0],-box[1]),'μ',font=face,fill=color)
    sharp.paste(tile.resize((round((r-l)*Z*SS),round((b-top)*Z*SS)),Image.Resampling.LANCZOS),tuple(round(v) for v in pt(0,0)))
   ox=255+f*305;im.paste(original,(ox,y));im.paste(sharp.resize(original.size,Image.Resampling.LANCZOS),(ox+110,y))
 im.save(a.output/f'pending-symbols-{page+1}.png')
print(a.output)
