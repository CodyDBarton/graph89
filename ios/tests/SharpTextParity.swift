import Foundation
@main struct Parity {
    static func dump(_ cells:[SharpTextRecognizer.Cell])->String {
        cells.map { c in let g=c.glyph; return "\(c.x),\(c.y),\(c.inverse ? 1:0),\(g.font),\(g.width),\(g.height),\(g.character),\(g.dynamic ? 1:0)" }.sorted().joined(separator:";")
    }
    static func main() throws {
        let args=CommandLine.arguments
        let r=SharpTextRecognizer(Array(try Data(contentsOf:URL(fileURLWithPath:args[1]))))
        var previous:[SharpTextRecognizer.Cell]=[]
        for path in args.dropFirst(2) {
            let p=(try Data(contentsOf:URL(fileURLWithPath:path))).map {$0 != 0}
            print("fresh:"+dump(r.recognize(p)));previous=r.stable(p,previous);print("stable:"+dump(previous))
        }
    }
}
