import Foundation
import CoreText
@main struct FontCheck {
    static func main() throws {
        let url=URL(fileURLWithPath:CommandLine.arguments[1])
        let ds=CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor]
        let font=CTFontCreateWithFontDescriptor(ds[0],2048,nil)
        let entries=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:Any]]
        for e in entries {
            var ch=UniChar(e["preview"] as! Int), g:CGGlyph=0
            precondition(CTFontGetGlyphsForCharacters(font,&ch,&g,1) && g != 0)
            precondition(CTFontCreatePathForGlyph(font,g,nil) != nil)
        }
        var family=CGRect.null
        for c in 33..<127 {
            var ch=UniChar(c),g:CGGlyph=0
            precondition(CTFontGetGlyphsForCharacters(font,&ch,&g,1))
            if let p=CTFontCreatePathForGlyph(font,g,nil) { family=family.union(p.boundingBoxOfPath) }
        }
        precondition(abs(family.height-2032)<1 && abs(family.maxY-1602)<1,"Unexpected font bounds: \(family)")
        print("CoreText: all \(entries.count) approved symbols have outlines; ASCII family scale matches Android.")
    }
}
