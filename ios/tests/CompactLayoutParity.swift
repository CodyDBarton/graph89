import Foundation
@main struct CompactParity {
    static func main() throws {
        let a=CommandLine.arguments
        let r=SharpTextRecognizer(Array(try Data(contentsOf:URL(fileURLWithPath:a[1]))))
        for base in a.dropFirst(2) {
            let packets=try String(contentsOfFile:base+".packets",encoding:.utf8).split(whereSeparator:{$0.isWhitespace}).compactMap {Int32($0)}
            let scene=r.compactScene(packets)
            func q(_ x:Double)->Int { Int((x*1000).rounded(.toNearestOrAwayFromZero)) }
            var items=["\(scene.body ? 1:0),\(scene.input ? 1:0),\(scene.inputStart),\(scene.inputCount),\(scene.fullInputCount),\(scene.cursorX.map(q) ?? -1),\(scene.inverseRects.count),\(scene.inverseRects.reduce(0) {$0+q($1[3])}),\(scene.markerOffsets.reduce(0) {$0+q($1)}),\(q(scene.verticalSaved)),\(scene.repackedHistory ? 1:0),\(scene.visibleHistoryEntries),\(q(scene.historySaved))"]
            for item in scene.items {
                items.append("\(q(item.x)),\(q(item.y)),\(q(item.scale)),\(item.inverse ? 1:0),\(item.glyph?.character ?? -1),\(item.glyph?.width ?? q(item.x1)),\(item.glyph?.height ?? q(item.y1)),\(q(item.advance)),\(item.selectionX.map(q) ?? -1),\(q(item.heightScale))")
            }
            print(items.joined(separator:";"))
        }
    }
}
