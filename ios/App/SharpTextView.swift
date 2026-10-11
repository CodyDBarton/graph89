import UIKit
import CoreText

// Vector replacement layer, using the identical approved font bundled by Android.
// Recognition reads the original LCD; it never reads pixels from its own artwork.
final class SharpTextView: UIView {
    var enabled = false {
        didSet { if enabled != oldValue { cells=[]; recognize(); setNeedsDisplay() } }
    }
    var compact = false { didSet { setNeedsDisplay() } }
    private var recognizer: SharpTextRecognizer?
    private var pixels: [Bool]=[]
    private var original = Data()
    private var retained: [Int32]=[]
    private var fallback: [SharpTextRecognizer.Cell]=[]
    private var cells: [SharpTextRecognizer.Cell]=[]
    private var font: CTFont?
    private var family = CGRect.null
    private var paths: [ObjectIdentifier: CGPath]=[:]
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isOpaque=false; contentMode = .redraw
        if let url=Bundle.main.url(forResource:"Graph89HD",withExtension:"ttf"),
           let descriptors=CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let descriptor=descriptors.first {
            let face=CTFontCreateWithFontDescriptor(descriptor,2048,nil)
            for c in 33..<127 { if let path=glyphPath(c,face) { family=family.union(path.boundingBoxOfPath) } }
            if !family.isNull { font=face }
        }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(_ data: Data) {
        recognizer = data.count==3*256*12 ? SharpTextRecognizer(Array(data)) : nil
        cells=[]; fallback=[]; paths=[:]; recognize(); setNeedsDisplay()
    }
    func update(_ data: Data, retained packets: [Int32]? = nil) {
        let next = packets ?? retained
        if data == original && next == retained { return }
        retained=next
        guard data.count==160*100 else { cells=[]; setNeedsDisplay(); return }
        original=data; pixels=SharpTextRecognizer.withoutCursor(data.map {$0==30},retained); recognize(); setNeedsDisplay()
    }
    private func recognize() {
        guard enabled, font != nil, pixels.count==160*100, let recognizer else { cells=[]; fallback=[]; accessibilityHint="retained:0"; accessibilityValue = "off:0"; return }
        fallback=recognizer.stable(pixels,fallback)
        cells=recognizer.retained(retained,fallback:fallback)
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {
            accessibilityIdentifier="retained:\(recognizer.retainedCount(retained))"
            accessibilityValue = "on:\(cells.count)"
            if ProcessInfo.processInfo.arguments.contains("--ui-test-inverse-trig") {
                let raised=cells.filter { $0.glyph.character==SharpTextRecognizer.special(180) }
                accessibilityValue="on:\(cells.count);raised:\(raised.count),inverse:\(raised.filter { $0.inverse }.count)"
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-test-cursor") {
                accessibilityValue="on:\(cells.count);entry:\(cells.filter { $0.y==85 && $0.glyph.font==1 }.count);cursor:\(SharpTextRecognizer.cursor(retained)?.mask ?? 0)"
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-test-compact-layout") {
                let scene=recognizer.compactScene(retained)
                let beyond=scene.items.filter { $0.glyph != nil && $0.scale==0.72 && $0.x>118 && $0.x<160 }.count
                accessibilityValue="on:\(cells.count);compact:\(compact ? 1:0),input:\(scene.inputCount),full:\(scene.fullInputCount),body:\(scene.body ? 1:0),start:\(scene.inputStart),caret:\(scene.cursorX ?? -1),yeditor:\(scene.yEditor ? 1:0),extra:\(scene.extraRows),beyond:\(beyond)"
            }
            let clipped=cells.filter { $0.y<$0.clipTop || $0.y+$0.glyph.height>$0.clipBottom || $0.x<$0.clipLeft || $0.x+$0.glyph.width>$0.clipRight }
            if ProcessInfo.processInfo.arguments.contains("--ui-test-clipped-math") {
                if compact {
                    let rendered=recognizer.compactScene(retained).items.filter { $0.glyph?.dynamic == true }
                    accessibilityValue="on:\(cells.count);compact:1,math:\(rendered.count),inverse:\(rendered.filter { $0.inverse }.count)"
                } else { accessibilityValue="on:\(cells.count);clipped:\(clipped.count),math:\(clipped.filter { $0.glyph.dynamic }.count),inverse:\(clipped.filter { $0.glyph.dynamic && $0.inverse }.count)" }
            }
        }
    }
    private func glyphPath(_ code:Int,_ face:CTFont)->CGPath? {
        var ch=UniChar(code), glyph:CGGlyph=0
        guard CTFontGetGlyphsForCharacters(face,&ch,&glyph,1), glyph != 0 else { return nil }
        return CTFontCreatePathForGlyph(face,glyph,nil)
    }
    private func outline(_ g:SharpTextRecognizer.Glyph)->CGPath? {
        let id=ObjectIdentifier(g); if let path=paths[id] { return path }
        if g.character==SharpTextRecognizer.dropdown {
            let path=CGMutablePath();path.move(to:.zero);path.addLine(to:CGPoint(x:3,y:0));path.addLine(to:CGPoint(x:1.5,y:2));path.closeSubpath();paths[id]=path;return path
        }
        if g.character==SharpTextRecognizer.special(18) {
            let path=CGMutablePath()
            path.move(to:CGPoint(x:CGFloat(g.minX),y:CGFloat(g.minY)))
            path.addLine(to:CGPoint(x:CGFloat(g.maxX+1),y:CGFloat(g.minY+g.maxY+1)/2))
            path.addLine(to:CGPoint(x:CGFloat(g.minX),y:CGFloat(g.maxY+1)))
            path.closeSubpath();paths[id]=path;return path
        }
        if g.character==SharpTextRecognizer.special(180) {
            // Match the approved size-specific composition at 200 units/pixel.
            guard let font, let path=glyphPath(0xe300+g.font,font) else { return nil }
            var matrix=CGAffineTransform(a:1.0/200,b:0,c:0,d:-1.0/200,tx:0,ty:10)
            let transformed=path.copy(using:&matrix);paths[id]=transformed;return transformed
        }
        guard let font, let path=glyphPath(g.character,font) else { return nil }
        let b=path.boundingBoxOfPath
        var scale=(CGFloat(g.height)-0.1)/family.height
        if b.width>0 { scale=min(scale,(CGFloat(g.width)-0.1)/b.width) }
        var ch=UniChar(g.character), glyph:CGGlyph=0, advance=CGSize.zero
        CTFontGetGlyphsForCharacters(font,&ch,&glyph,1)
        CTFontGetAdvancesForGlyphs(font,.horizontal,&glyph,&advance,1)
        var matrix:CGAffineTransform
        if g.dynamic && !b.isEmpty {
            let sx=(CGFloat(g.width)-0.1)/b.width, sy=(CGFloat(g.height)-0.1)/b.height
            matrix=CGAffineTransform(a:sx,b:0,c:0,d:-sy,tx:0.05-b.minX*sx,ty:0.05+b.maxY*sy)
        } else {
            matrix=CGAffineTransform(a:scale,b:0,c:0,d:-scale,
                tx:(CGFloat(g.width)-advance.width*scale)/2,ty:0.05+family.maxY*scale)
        }
        let transformed=path.copy(using:&matrix); paths[id]=transformed; return transformed
    }
    private func drawCompact(_ scene:SharpTextRecognizer.CompactScene,_ context:CGContext) {
        context.saveGState()
        // History markers are outside Print2DExpr. Keep them aligned with the
        // transformed history rather than leaving the old row position behind.
        if scene.yEditor {
            var remaining=pixels
            for r in scene.eraseRects {
                let x0=max(0,Int(r[0])),x1=min(160,Int(ceil(r[0]+r[2])))
                let y0=max(16,Int(r[1])),y1=min(83,Int(ceil(r[1]+r[3])))
                if x1>x0 && y1>y0 {for y in y0..<y1 {for x in x0..<x1 {remaining[y*160+x]=r[4] != 0}}}
            }
            let raster=CGMutablePath()
            for y in 16..<83 {
                var x=0
                while x<160 {
                    if !remaining[y*160+x] {x += 1;continue}
                    let left=x
                    while x<160 && remaining[y*160+x] {x += 1}
                    raster.addRect(CGRect(x:Double(left)*0.72,y:16+Double(y-16)*0.72,width:Double(x-left)*0.72,height:0.72))
                }
            }
            context.setFillColor(UIColor(white:30/255.0,alpha:1).cgColor)
            context.addPath(raster);context.fillPath()
        } else if scene.body {
            context.setFillColor(UIColor(white:30/255.0,alpha:1).cgColor)
            let markers=CGMutablePath()
            for x in 0..<6 {
                var y=16
                while y<83 {
                    if !pixels[y*160+x] { y += 1;continue }
                    let top=y
                    while y<83 && pixels[y*160+x] { y += 1 }
                    markers.addRect(CGRect(x:Double(x),y:83+Double(top-83)*0.72,width:1,height:Double(y-top)*0.72))
                }
            }
            context.addPath(markers);context.fillPath()
        }
        context.saveGState();context.clip(to:CGRect(x:0,y:scene.yEditor ? 21.04:16,width:160,height:scene.yEditor ? 61.96:67))
        context.setFillColor(UIColor(white:30/255.0,alpha:1).cgColor)
        for r in scene.inverseRects { context.fill(CGRect(x:r[0],y:r[1],width:r[2],height:r[3])) }
        context.restoreGState()
        for item in scene.items where item.inverse && item.glyph != nil && item.scale==0.8 {
            let g=item.glyph!
            context.saveGState();context.clip(to:CGRect(x:0,y:item.y>=84 ? 84:16,width:160,height:item.y>=84 ? 9:67))
            context.setFillColor(UIColor(white:30/255.0,alpha:1).cgColor)
            context.fill(CGRect(x:item.x-0.5,y:item.y,width:item.scale==0.8 ? 4.5:Double(g.width+1)*item.scale,height:Double(g.height)*item.scale))
            context.restoreGState()
        }
        for item in scene.items {
            context.saveGState()
            context.clip(to:CGRect(x:0,y:item.scale==0.8 ? 84:item.clipTop,width:160,height:item.scale==0.8 ? 9:83-item.clipTop))
            let color=UIColor(white:(item.inverse ? 210:30)/255.0,alpha:1).cgColor
            context.setFillColor(color);context.setStrokeColor(color)
            if let g=item.glyph {
                context.translateBy(x:item.x,y:item.y);context.scaleBy(x:item.scale,y:item.scale)
                if g.character != 0,let path=outline(g) { context.addPath(path);context.fillPath() }
                else { for y in 0..<g.height { for x in 0..<g.width where g.rows[y]&(1<<(g.width-x-1)) != 0 { context.fill(CGRect(x:x,y:y,width:1,height:1)) } } }
            } else if item.attribute != 0 {
                context.setLineWidth(item.scale)
                context.setLineCap(.square)
                context.move(to:CGPoint(x:item.x+item.scale/2,y:item.y+item.scale/2))
                context.addLine(to:CGPoint(x:item.x1+item.scale/2,y:item.y1+item.scale/2));context.strokePath()
                if item.x==item.x1 && item.y==item.y1 { context.fill(CGRect(x:item.x,y:item.y,width:item.scale,height:item.scale)) }
            }
            context.restoreGState()
        }
        if let x=scene.cursorX,let cursor=SharpTextRecognizer.cursor(retained) {
            context.setFillColor(UIColor(white:30/255.0,alpha:1).cgColor)
            for y in 0..<8 where cursor.mask&(1<<y) != 0 { context.fill(CGRect(x:x,y:85.8+Double(y)*0.8,width:0.6,height:0.8)) }
        }
        context.restoreGState()
    }
    override func draw(_ rect:CGRect) {
        guard enabled, let context=UIGraphicsGetCurrentContext(), pixels.count==160*100 else { return }
        // Clear in native pixel coordinates before scaling. Erasing separately
        // above a UIImageView can leave subpixel fragments at fractional zoom.
        let scene = compact ? recognizer?.compactScene(retained) : nil
        var cleaned = pixels.map { UInt8($0 ? 30:210) }
        if scene?.body == true { for y in 16..<83 { for x in 0..<160 { cleaned[y*160+x]=210 } } }
        if scene?.input == true { for y in 84..<93 { for x in 0..<160 { cleaned[y*160+x]=210 } } }
        for cell in cells {
            if scene?.body == true && cell.y<83 && cell.y+cell.glyph.height>16 { continue }
            if scene?.input == true && cell.y==85 { continue }
            let g=cell.glyph
            for y in g.minY...g.maxY { for x in g.minX...g.maxX where cell.x+x>=cell.clipLeft && cell.x+x<cell.clipRight && cell.y+y>=cell.clipTop && cell.y+y<cell.clipBottom {
                cleaned[(cell.y+y)*160+cell.x+x] = cell.inverse ? 30:210
            } }
        }
        guard let provider=CGDataProvider(data:Data(cleaned) as CFData),
              let image=CGImage(width:160,height:100,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:160,
                space:CGColorSpaceCreateDeviceGray(),bitmapInfo:[],provider:provider,decode:nil,
                shouldInterpolate:false,intent:.defaultIntent) else { return }
        context.saveGState();context.clip(to:bounds);context.scaleBy(x:bounds.width/160,y:bounds.height/100)
        context.saveGState();context.interpolationQuality = .none
        context.translateBy(x:0,y:100);context.scaleBy(x:1,y:-1)
        context.draw(image,in:CGRect(x:0,y:0,width:160,height:100));context.restoreGState()
        for cell in cells {
            if scene?.body == true && cell.y<83 && cell.y+cell.glyph.height>16 { continue }
            if scene?.input == true && cell.y==85 { continue }
            let g=cell.glyph; guard g.character != 0, let path=outline(g) else { continue }
            context.saveGState()
            context.clip(to:CGRect(x:cell.clipLeft,y:cell.clipTop,width:cell.clipRight-cell.clipLeft,height:cell.clipBottom-cell.clipTop))
            context.translateBy(x:CGFloat(cell.x),y:CGFloat(cell.y))
            let clip=CGMutablePath();clip.addRect(CGRect(x:0,y:0,width:g.width,height:g.height))
            for y in max(0,cell.clipTop-cell.y)..<min(g.height,cell.clipBottom-cell.y) { for x in max(0,cell.clipLeft-cell.x)..<min(g.width,cell.clipRight-cell.x) {
                if x>=g.minX && x<=g.maxX && y>=g.minY && y<=g.maxY { continue }
                if pixels[(cell.y+y)*160+cell.x+x] != cell.inverse { clip.addRect(CGRect(x:x,y:y,width:1,height:1)) }
            } }
            context.addPath(clip);context.clip(using:.evenOdd)
            context.setFillColor(UIColor(white:(cell.inverse ? 210:30)/255.0,alpha:1).cgColor)
            context.addPath(path);context.fillPath();context.restoreGState()
        }
        if let scene { drawCompact(scene,context) }
        if scene?.input != true, let cursor=SharpTextRecognizer.cursor(retained) {
            context.setFillColor(UIColor(white:30/255.0,alpha:1).cgColor)
            for y in 0..<8 where cursor.mask&(1<<y) != 0 {
                context.fill(CGRect(x:Double(cursor.x)+0.7,y:Double(85+y),width:0.6,height:1))
            }
        }
        context.restoreGState()
    }
}
