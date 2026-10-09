"""Preview-only derivative d and toolbar dropdown arrow; no app assets changed."""
from pathlib import Path
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parents[2]
fonts=(root/'build/sharp-text-test/fonts.bin').read_bytes()
f=TTFont(root/'app/src/main/assets/fonts/Graph89HD.ttf')
for t in f['cmap'].tables:
    if t.isUnicode() and t.format in (4,12):t.cmap[0xe1bc]='uniE008'
preview=root/'build/font-comparison/home-symbols-preview-only.ttf';f.save(preview)
scale=14;ss=4;bg=(182,196,182)
label=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',20)
small=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',16)
im=Image.new('RGB',(720,650),'#fafaf7');d=ImageDraw.Draw(im)
d.text((20,15),'New Home symbols — preview only',font=label,fill='#222')
d.text((20,45),'Original ROM pixels                  Proposed sharp outline',font=small,fill='#555')
for font_id,title in enumerate(['Derivative d — small font','Derivative d — input / pretty print','Derivative d — large font']):
    y=90+font_id*160;d.text((20,y),title,font=small,fill='#222')
    off=(font_id*256+188)*12;w,h=fonts[off:off+2]
    original=Image.new('RGB',(w*scale,h*scale),bg);p=ImageDraw.Draw(original)
    for row,b in enumerate(fonts[off+2:off+2+h]):
        for x in range(w):
            if b&(128>>x):p.rectangle((x*scale,row*scale,(x+1)*scale-1,(row+1)*scale-1),fill='black')
    g=f['glyf']['uniE008'];g.recalcBounds(f['glyf'])
    fit=min((h-.1)/2032,(w-.1)/(g.xMax-g.xMin));size=round(2048*fit*scale*ss)
    face=ImageFont.truetype(str(preview),size);ch=chr(0xe1bc)
    sharp=Image.new('RGB',(w*scale*ss,h*scale*ss),bg);p=ImageDraw.Draw(sharp)
    p.text(((w*scale*ss-face.getlength(ch))/2,(.05+1602*fit)*scale*ss),ch,font=face,fill='black',anchor='ls')
    im.paste(original,(60,y+25));im.paste(sharp.resize(original.size,Image.Resampling.LANCZOS),(370,y+25))
y=580;d.text((20,y),'Toolbar dropdown arrow — same 3 × 2 pixel footprint',font=small,fill='#222')
a=Image.new('RGB',(3*scale,2*scale),bg);p=ImageDraw.Draw(a);p.rectangle((0,0,3*scale-1,scale-1),fill='black');p.rectangle((scale,scale,2*scale-1,2*scale-1),fill='black')
b=Image.new('RGB',(3*scale*ss,2*scale*ss),bg);p=ImageDraw.Draw(b);p.polygon([(0,0),(3*scale*ss-1,0),(1.5*scale*ss,2*scale*ss-1)],fill='black')
im.paste(a,(60,y+30));im.paste(b.resize(a.size,Image.Resampling.LANCZOS),(370,y+30))
im.save(Path(__file__).with_name('pending-home-symbols.png'))
