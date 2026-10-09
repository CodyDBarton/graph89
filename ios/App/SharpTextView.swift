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
        cells=[]; paths=[:]; recognize(); setNeedsDisplay()
    }
    func update(_ data: Data) {
        guard data.count==160*100 else { cells=[]; setNeedsDisplay(); return }
        original=data; pixels=data.map {$0==30}; recognize(); setNeedsDisplay()
    }
    private func recognize() {
        guard enabled, font != nil, pixels.count==160*100, let recognizer else { cells=[]; accessibilityValue = "off:0"; return }
        cells=recognizer.stable(pixels,cells)
        if ProcessInfo.processInfo.arguments.contains("--ui-test") { accessibilityValue = "on:\(cells.count)" }
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
        var cleaned = [UInt8](original)
        for cell in cells {
            let g=cell.glyph
            for y in g.minY...g.maxY { for x in g.minX...g.maxX where cell.x+x<160 {
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
            context.saveGState();context.translateBy(x:CGFloat(cell.x),y:CGFloat(cell.y))
            let clip=CGMutablePath();clip.addRect(CGRect(x:0,y:0,width:g.width,height:g.height))
            for y in 0..<g.height { for x in 0..<min(g.width,160-cell.x) {
                if x>=g.minX && x<=g.maxX && y>=g.minY && y<=g.maxY { continue }
                if pixels[(cell.y+y)*160+cell.x+x] != cell.inverse { clip.addRect(CGRect(x:x,y:y,width:1,height:1)) }
            } }
            context.addPath(clip);context.clip(using:.evenOdd)
            context.setFillColor(UIColor(white:(cell.inverse ? 210:30)/255.0,alpha:1).cgColor)
            context.addPath(path);context.fillPath();context.restoreGState()
        }
        context.restoreGState()
    }
}
