import Foundation
@main struct RetainedParity {
    static func main() throws {
        let a=CommandLine.arguments
        let r=SharpTextRecognizer(Array(try Data(contentsOf:URL(fileURLWithPath:a[1]))))
        var previous:[SharpTextRecognizer.Cell]=[]
        var bases:[String]=[]
        for value in a.dropFirst(2) {
            if value.hasPrefix("@") {bases += try String(contentsOfFile:String(value.dropFirst()),encoding:.utf8).split(separator:"\n").map(String.init)}
            else {bases.append(value)}
        }
        for base in bases {
            var p=Array(try Data(contentsOf:URL(fileURLWithPath:base+".pixels"))).map {$0 != 0}
            let packets=try String(contentsOfFile:base+".packets",encoding:.utf8).split(whereSeparator:{$0.isWhitespace}).compactMap {Int32($0)}
            p=SharpTextRecognizer.withoutCursor(p,packets)
            previous=r.stable(p,previous)
            let cells=r.retained(packets,fallback:previous)
            print(cells.map { c in let g=c.glyph;return "\(c.x),\(c.y),\(g.font),\(g.character),\(c.inverse ? 1:0),\(g.width),\(g.height),\(c.shaded ? 1:0)" }.sorted().joined(separator:";"))
        }
    }
}
