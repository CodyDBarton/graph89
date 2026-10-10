import UIKit
import CoreText

// Vector replacement layer, using the identical approved font bundled by Android.
// Recognition reads the original LCD; it never reads pixels from its own artwork.
final class SharpTextView: UIView {
    var enabled = false {
        didSet { if enabled != oldValue { cells=[]; recognize(); setNeedsDisplay() } }
    }
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
            let clipped=cells.filter { $0.y<$0.clipTop || $0.y+$0.glyph.height>$0.clipBottom || $0.x<$0.clipLeft || $0.x+$0.glyph.width>$0.clipRight }
            if ProcessInfo.processInfo.arguments.contains("--ui-test-clipped-math") { accessibilityValue="on:\(cells.count);clipped:\(clipped.count),math:\(clipped.filter { $0.glyph.dynamic }.count),inverse:\(clipped.filter { $0.glyph.dynamic && $0.inverse }.count)" }
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
    override func draw(_ rect:CGRect) {
        guard enabled, let context=UIGraphicsGetCurrentContext(), pixels.count==160*100 else { return }
        // Clear in native pixel coordinates before scaling. Erasing separately
        // above a UIImageView can leave subpixel fragments at fractional zoom.
        var cleaned = pixels.map { UInt8($0 ? 30:210) }
        for cell in cells {
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
        if let cursor=SharpTextRecognizer.cursor(retained) {
            context.setFillColor(UIColor(white:30/255.0,alpha:1).cgColor)
            for y in 0..<8 where cursor.mask&(1<<y) != 0 {
                context.fill(CGRect(x:Double(cursor.x)+0.7,y:Double(85+y),width:0.6,height:1))
            }
        }
        context.restoreGState()
    }
}
