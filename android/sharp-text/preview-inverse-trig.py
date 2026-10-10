"""Preview only: reuse approved minus/1 outlines for ROM character 180."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parents[2]
font=TTFont(root/'app/src/main/assets/fonts/Graph89HD.ttf')
rom=(root/'build/sharp-text-test/fonts.bin').read_bytes()
preview=root/'build/font-comparison/inverse-trig-preview-only.ttf'
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
    name='previewInverse'+str(f);font['glyf'][name]=pen.glyph()
    font['hmtx'].metrics[name]=(1600,0)
    font.setGlyphOrder(list(dict.fromkeys(font.getGlyphOrder()+[name])))
    for table in font['cmap'].tables:
        if table.isUnicode() and table.format in (4,12):table.cmap[0xe300+f]=name
font.save(preview)
label=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',21)
small=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',17)
image=Image.new('RGB',(930,760),'#fafaf7');d=ImageDraw.Draw(image)
d.text((24,18),'Inverse trig: raised −1 — preview only',font=label,fill='#222')
d.text((24,52),'Existing approved minus and 1; app font unchanged',font=small,fill='#555')
d.text((220,90),'Original pixels',font=small,fill='#222')
d.text((580,90),'Proposed sharp',font=small,fill='#222')
for x in [220,580]:
    d.text((x,118),'Normal',font=small,fill='#555')
    d.text((x+170,118),'Inverted',font=small,fill='#555')
zoom=18;ss=4
for f,title in enumerate(['Small','Input / pretty print','Large']):
    y=150+f*200;d.text((24,y+30),title,font=small,fill='#222')
    off=(f*256+180)*12;w,h=rom[off:off+2]
    for inverse in [False,True]:
        bg,fg=((30,30,30),(210,210,210)) if inverse else ((210,210,210),(30,30,30))
        # Side by side within each column: normal and selected/inverted.
        ox=220+inverse*170;sx=580+inverse*170
        assert ox+w*zoom <= 580 and sx+w*zoom <= image.width
        assert y+h*zoom <= image.height
        original=Image.new('RGB',(w*zoom,h*zoom),bg);p=ImageDraw.Draw(original)
        for row,bits in enumerate(rom[off+2:off+2+h]):
            for x in range(w):
                if bits&(128>>x):p.rectangle((x*zoom,row*zoom,(x+1)*zoom-1,(row+1)*zoom-1),fill=fg)
        sharp=Image.new('RGB',(w*zoom*ss,h*zoom*ss),bg);p=ImageDraw.Draw(sharp)
        face=ImageFont.truetype(str(preview),round(2048/200*zoom*ss))
        p.text((0,10*zoom*ss),chr(0xe300+f),font=face,fill=fg,anchor='ls')
        image.paste(original,(ox,y));image.paste(sharp.resize(original.size,Image.Resampling.LANCZOS),(sx,y))
image.save(Path(__file__).with_name('pending-inverse-trig-v2.png'))
