import Foundation

// Exact ROM bitmap matching. Keep this behavior in parity with Android's
// SharpTextRecognizer; this file has no UIKit dependencies so fixtures can test it.
final class SharpTextRecognizer {
    static let dropdown = 0xe200
    static func special(_ code: Int) -> Int {
        let approved = [18,22,28,29,30,31,128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,160,168,176,177,180,183,188,189,190]
        return approved.contains(code) ? 0xe100 + code : 0
    }
    final class Glyph {
        let font: Int, width: Int, height: Int, character: Int, rows: [Int], dynamic: Bool
        let ink: Int, minX: Int, maxX: Int, minY: Int, maxY: Int
        init(_ font: Int, _ width: Int, _ height: Int, _ character: Int, _ rows: [Int], dynamic: Bool = false) {
            self.font=font; self.width=width; self.height=height; self.character=character; self.rows=rows; self.dynamic=dynamic
            var n=0, left=width, right = -1, top=height, bottom = -1
            for y in 0..<height { for x in 0..<width where rows[y] & (1 << (width-x-1)) != 0 {
                n += 1; left=min(left,x); right=max(right,x); top=min(top,y); bottom=max(bottom,y)
            } }
            ink=n; minX=left; maxX=right; minY=top; maxY=bottom
        }
    }
    struct Cell {
        let x:Int,y:Int,inverse:Bool,glyph:Glyph
        var clipLeft=0,clipTop=0,clipRight=160,clipBottom=100
    }
    struct Run {
        var cells: [Cell]=[]; var letters=0, ink=0, font=0
        var text: String { String(cells.compactMap { UnicodeScalar($0.glyph.character).map(Character.init) }) }
    }
    private var capturedGlyphs: [[Glyph?]] = Array(repeating: Array(repeating: nil, count: 256), count: 3)
    private var tables: [[UInt64:[Glyph]]] = Array(repeating: [:], count: 3)
    private var widths: [[Int]] = Array(repeating: [], count: 3)
    private var labels: [Int:Glyph]=[:], dynamic: [String:Glyph]=[:], labelIs: [ObjectIdentifier:Glyph]=[:]
    private var blocked: [Bool]=[], graph=false, input = -1
    private let arrow = Glyph(0,3,2,SharpTextRecognizer.dropdown,[7,2],dynamic:true)
    init(_ bytes: [UInt8]) {
        precondition(bytes.count == 3*256*12)
        for f in 0..<3 { for c in 0..<256 {
            let approved = (33..<127).contains(c) ? c : Self.special(c)
            if approved == 0 { continue }
            let off=(f*256+c)*12, w=Int(bytes[off]), h=Int(bytes[off+1])
            if w<1 || w>8 || h<4 || h>10 { continue }
            let rows=(0..<h).map { Int(bytes[off+2+$0]) >> (8-w) }
            let ch = f==0 && (c==73 || c==124) ? 0 : approved
            let g=Glyph(f,w,h,ch,rows); if g.ink==0 { continue }
            capturedGlyphs[f][c] = ch == approved ? g : Glyph(f,w,h,approved,rows)
            if f==0 && (c==70 || (49...56).contains(c)) { labels[c]=g }
            tables[f][key(w,rows),default:[]].append(g)
            if !widths[f].contains(w) { widths[f].append(w) }
        } }
    }
    // Identity is supplied by the ROM call. No bitmap classification is used.
    private var framePixels:[Bool]=[], homeFrame=false
    private func captured(_ packets: [Int32]) -> [Cell] {
        var direct: [Cell] = []
        for i in stride(from:0,to:packets.count-packets.count%12,by:12) {
            let x=Int(packets[i]),y=Int(packets[i+1]),f=Int(packets[i+2]),c=Int(packets[i+3])
            guard (0...3).contains(f),(0..<256).contains(c),packets[i+7] != 3 else { continue }
            var glyph:Glyph?
            if f<3 { glyph=capturedGlyphs[f][c] }
            else {
                let h=Int(packets[i+6]),w=c==189 ? 5:3
                guard (7...512).contains(h),[189,40,41].contains(c),Int(packets[i+5])==w else { continue }
                var rows=Array(repeating:c==189 ? 4:c==40 ? 4:1,count:h)
                rows[0]=c==189 ? 2:c==40 ? 1:4;rows[h-1]=rows[0];rows[1]=2;rows[h-2]=2
                if c==189 { rows[1]=5;rows[h-2]=20;rows[h-1]=8 }
                glyph=cached("native:\(c):\(h)",rows,w,c==189 ? Self.special(189):c)
            }
            let l=Int(packets[i+8]),t=Int(packets[i+9]),r=Int(packets[i+10]),b=Int(packets[i+11])
            guard let g=glyph,g.width==Int(packets[i+5]),g.height==Int(packets[i+6]),
                  l>=0,t>=0,r<=160,b<=100,l<r,t<b,x+g.width>l,x<r,y+g.height>t,y<b else { continue }
            direct.append(Cell(x:x,y:y,inverse:packets[i+4] != 0,glyph:g,clipLeft:l,clipTop:t,clipRight:r,clipBottom:b))
        }
        return direct
    }
    func retainedCount(_ packets: [Int32]) -> Int { captured(packets).count }
    func retained(_ packets: [Int32], fallback: [Cell]) -> [Cell] {
        let direct=captured(packets)
        let result = direct + fallback.filter { c in !direct.contains { d in
            c.x < min(d.clipRight,d.x+d.glyph.width) && max(d.clipLeft,d.x) < c.x+c.glyph.width && c.y < min(d.clipBottom,d.y+d.glyph.height) && max(d.clipTop,d.y) < c.y+c.glyph.height
        } }
        guard framePixels.count==16000,homeFrame,!graph else { return result }
        var occupied=blocked
        if input>=0 { for y in input..<input+8 { for x in 0..<160 { occupied[y*160+x]=true } } }
        for c in direct { occupy(c,&occupied,160) }
        var shaped=result
        integrals(framePixels,160,100,&occupied,result,&shaped,true)
        parentheses(framePixels,160,100,&occupied,&shaped)
        let shapes=Array(shaped.dropFirst(result.count))
        return result.filter { c in !shapes.contains { d in
            c.x<d.x+d.glyph.width && d.x<c.x+c.glyph.width && c.y<d.y+d.glyph.height && d.y<c.y+c.glyph.height
        } } + shapes
    }
    private func key(_ w: Int, _ rows: [Int]) -> UInt64 {
        var k=UInt64(w); for y in 0..<4 { k=(k << 8)|UInt64(rows[y]) }; return k
    }
    private func anchor(_ ch: Int) -> Bool {
        if let c=UnicodeScalar(ch), CharacterSet.alphanumerics.contains(c) { return true }
        return ch>=0xe100 && Self.special(ch-0xe100)==ch
    }
    private func row(_ p: [Bool], _ sw: Int, _ x: Int, _ y: Int, _ w: Int, _ inverse: Bool) -> Int {
        var value=0
        for i in 0..<w { value=(value << 1) | ((x+i<sw && p[y*sw+x+i] != inverse) ? 1:0) }
        return value
    }
    private func match(_ p: [Bool], _ sw: Int, _ sh: Int, _ f: Int, _ x: Int, _ y: Int) -> Cell? {
        var best: Cell?
        for w in widths[f] {
            if x+w>sw+1 { continue }
            for inverse in [false,true] {
                let h=[5,8,10][f]
                var cursor=x+w<sw && y+h<=sh
                if cursor { for j in 0..<h { if p[(y+j)*sw+x+w-1]==inverse || p[(y+j)*sw+x+w]==inverse { cursor=false; break } } }
                for masked in 0...(cursor ? 1:0) {
                    let mask=masked==1 ? ~1 : -1
                    let k=key(w,(0..<4).map { row(p,sw,x,y+$0,w,inverse)&mask })
                    guard let candidates=tables[f][k] else { continue }
                    for g in candidates {
                        if y+g.height>sh { continue }
                        var same=true
                        for j in 0..<g.height {
                            if (masked==1 && g.rows[j]&1 != 0) || row(p,sw,x,y+j,w,inverse)&mask != g.rows[j] { same=false; break }
                        }
                        if same && (best==nil || w>best!.glyph.width || (w==best!.glyph.width && g.ink>best!.glyph.ink)) {
                            best=Cell(x:x,y:y,inverse:inverse,glyph:g)
                        }
                    }
                }
            }
        }
        return best
    }
    private func blank(_ p: [Bool], _ sw: Int, _ x0: Int, _ x1: Int, _ y: Int, _ h: Int, _ inv: Bool) -> Bool {
        if x0<0 || x1>sw { return false }
        for j in y..<y+h { for x in x0..<x1 { if p[j*sw+x] != inv { return false } } }; return true
    }
    private func overlaps(_ c: Cell, _ mask: [Bool], _ sw: Int) -> Bool {
        for y in max(c.y,c.clipTop)..<min(c.clipBottom,c.y+c.glyph.height) { for x in max(c.x,c.clipLeft)..<min(c.clipRight,c.x+c.glyph.width) { if mask[y*sw+x] { return true } } }; return false
    }
    private func occupy(_ c: Cell, _ mask: inout [Bool], _ sw: Int) {
        for y in max(c.y,c.clipTop)..<min(c.clipBottom,c.y+c.glyph.height) { for x in max(c.x,c.clipLeft)..<min(c.clipRight,c.x+c.glyph.width) { mask[y*sw+x]=true } }
    }
    private func border(_ c: Cell, _ p: [Bool], _ sw: Int, _ sh: Int) -> Bool {
        let g=c.glyph, left=c.x+g.minX, right=c.x+g.maxX, top=c.y+g.minY, bottom=c.y+g.maxY
        for y in top-1...bottom+1 { for x in left-1...right+1 {
            if x>=left && x<=right && y>=top && y<=bottom { continue }
            if x>=0 && x<sw && y>=0 && y<sh && p[y*sw+x] != c.inverse { return false }
        } }; return true
    }
    private func exact(_ c: Cell, _ p: [Bool], _ sw: Int) -> Bool {
        for y in 0..<c.glyph.height { if row(p,sw,c.x,c.y+y,c.glyph.width,c.inverse) != c.glyph.rows[y] { return false } }; return true
    }
    private func homeBorders(_ p: [Bool], _ sw: Int, _ sh: Int) -> Bool {
        if sw != 160 || sh != 100 { return false }
        for x in 0..<sw { if !p[(sh-17)*sw+x] || !p[(sh-7)*sw+x] { return false } }; return true
    }
    private func exclusions(_ p: [Bool], _ sw: Int, _ sh: Int) -> [Bool] {
        var out=Array(repeating:false,count:p.count)
        guard sh>=16, let f=labels[70], (0..<sw).allSatisfy({p[15*sw+$0]}) else { return out }
        var left = -1
        for right in 0..<sw {
            if !p[7*sw+right] || !p[13*sw+right] || !p[14*sw+right] { continue }
            if left>=0 && right-left>=8 {
                var label=false, content=false
                for x in left+1..<right where x+f.width<right {
                    for inv in [false,true] {
                        if !exact(Cell(x:x,y:2,inverse:inv,glyph:f),p,sw) { continue }
                        for d in 49...56 { if let n=labels[d], x+f.width+n.width<=right,
                            exact(Cell(x:x+f.width,y:2,inverse:inv,glyph:n),p,sw) { label=true } }
                    }
                }
                for y in 2...12 { for x in left+1..<right { content = content || p[y*sw+x] } }
                if content && !label { for y in 0..<15 { for x in left+1..<right { out[y*sw+x]=true } } }
            }
            left=right
        }; return out
    }
    private func exponential(_ r: Run) -> Bool {
        if r.font==0 || r.cells.count<3 { return false }
        for i in 0..<r.cells.count-2 {
            let e=r.cells[i], c=r.cells[i+1], o=r.cells[i+2]
            if (e.glyph.character==Self.special(150) || e.glyph.character==101) && c.glyph.character==94 && o.glyph.character==40 && e.x+e.glyph.width==c.x && c.x+c.glyph.width==o.x { return true }
        }; return false
    }
    private func smallI(_ r: Run, _ index: Int, _ p: [Bool], _ sw: Int, _ sh: Int) -> Bool {
        let c=r.cells[index]; if !(c.y<14 || c.y>=sh-12) { return false }
        let stem=c.x+c.glyph.minX, bottom=c.y+c.glyph.height
        if c.y>=2 && p[(c.y-1)*sw+stem] != c.inverse && p[(c.y-2)*sw+stem] != c.inverse { return false }
        if bottom+1<sh && p[bottom*sw+stem] != c.inverse && p[(bottom+1)*sw+stem] != c.inverse { return false }
        func letter(_ ch: Int) -> Bool { UnicodeScalar(ch).map { CharacterSet.letters.contains($0) } ?? false }
        if index>0 { let b=r.cells[index-1]; if letter(b.glyph.character) && b.x+b.glyph.width==c.x { return true } }
        if index+1<r.cells.count { let a=r.cells[index+1]; if letter(a.glyph.character) && c.x+c.glyph.width==a.x { return true } }; return false
    }
    func recognize(_ p: [Bool], _ sw: Int=160, _ sh: Int=100) -> [Cell] {
        precondition(p.count==sw*sh)
        blocked=exclusions(p,sw,sh)
        var runs:[Run]=[], singles:[Cell]=[], home=false, graph=false, tools=false, prgm=false
        for f in stride(from:2,through:0,by:-1) {
            let h=[5,8,10][f], gap=[2,6,8][f]
            for y in 0...sh-h {
                var line=[Cell?](repeating:nil,count:sw)
                for x in 0..<sw {
                    var c=match(p,sw,sh,f,x,y)
                    if let v=c, overlaps(v,blocked,sw) || (f==0 && v.inverse && y>=14 && y<sh-12 && !border(v,p,sw,sh)) { c=nil }
                    line[x]=c
                    if let c, anchor(c.glyph.character) { singles.append(c) }
                }
                for start in 0..<sw {
                    guard let first=line[start], anchor(first.glyph.character) else { continue }
                    var r=Run(); r.font=f; var current: Cell?=first
                    while let c=current {
                        r.cells.append(c); r.ink += c.glyph.ink; if anchor(c.glyph.character) { r.letters += 1 }
                        let end=c.x+c.glyph.width; var next: Cell?
                        if end<sw { for x in end...min(sw-1,end+gap) {
                            if let n=line[x], n.inverse==c.inverse { next=n; break }
                            if !blank(p,sw,x,x+1,y,h,c.inverse) { break }
                        } }; current=next
                    }
                    if (r.letters>=2 || exponential(r)) && r.ink>=8 {
                        runs.append(r)
                        if y<14 { let t=r.text; home = home || t.contains("Algebra"); tools = tools || t.contains("Tools"); prgm = prgm || t.contains("Prgm"); graph = graph || t.contains("Zoom") || t.contains("Trace") || t.contains("ReGraph") }
                    }
                }
            }
        }
        home = home || (tools && prgm && homeBorders(p,sw,sh)); self.graph=graph; homeFrame=home; framePixels=sw==160 && sh==100 ? p:[]
        runs.sort { $0.font != $1.font ? $0.font>$1.font : $0.ink>$1.ink }
        var occupied=blocked, result:[Cell]=[]
        input = home && !graph && homeBorders(p,sw,sh) ? sh-15 : -1
        if input>=0 {
            for x in stride(from:1,to:sw,by:6) { if let c=match(p,sw,sh,1,x,input), c.glyph.width==6 && c.glyph.character != 0 { result.append(c) } }
            for y in input..<input+8 { for x in 0..<sw { occupied[y*sw+x]=true } }
        }
        if home && !graph { integrals(p,sw,sh,&occupied,singles,&result,false) }
        for r in runs {
            if r.cells.contains(where:{overlaps($0,occupied,sw)}) { continue }
            for (i,c) in r.cells.enumerated() {
                occupy(c,&occupied,sw)
                if c.glyph.font==0 && c.glyph.character==0 {
                    if smallI(r,i,p,sw,sh) {
                        let id=ObjectIdentifier(c.glyph)
                        if labelIs[id]==nil { let g=c.glyph; labelIs[id]=Glyph(g.font,g.width,g.height,73,g.rows) }
                        result.append(Cell(x:c.x,y:c.y,inverse:c.inverse,glyph:labelIs[id]!))
                    }; continue
                }
                if c.glyph.character != 0 && !(graph && c.y>=14 && c.y<sh-12) { result.append(c) }
            }
        }
        if home && !graph {
            for c in singles {
                if c.inverse || c.y<14 || c.y+c.glyph.height>sh-12 || overlaps(c,occupied,sw) || !border(c,p,sw,sh) { continue }
                occupy(c,&occupied,sw); result.append(c)
            }
            parentheses(p,sw,sh,&occupied,&result)
        }
        dropdowns(p,sw,sh,&occupied,&result)
        return result
    }
    func stable(_ p: [Bool], _ previous: [Cell], _ sw: Int=160, _ sh: Int=100) -> [Cell] {
        let fresh=recognize(p,sw,sh); var result:[Cell]=[], occupied=Array(repeating:false,count:p.count)
        for c in previous {
            let g=c.glyph
            if input>=0 && c.y<input+8 && c.y+g.height>input { continue }
            if g.font==0 && g.character==73 && !fresh.contains(where:{$0.x==c.x && $0.y==c.y && $0.glyph.font==0 && $0.glyph.character==73}) { continue }
            if g.dynamic && !fresh.contains(where:{$0.glyph === g && $0.x==c.x && $0.y==c.y && $0.inverse==c.inverse}) { continue }
            if c.x<0 || c.y<0 || c.y+g.height>sh || c.x>=sw || overlaps(c,occupied,sw) || overlaps(c,blocked,sw) || (graph && c.y>=14 && c.y<sh-12) { continue }
            for inv in [false,true] {
                if g.font==0 && inv && c.y>=14 && c.y<sh-12 && !border(Cell(x:c.x,y:c.y,inverse:inv,glyph:g),p,sw,sh) { continue }
                var same=true
                for y in g.minY...g.maxY { for x in g.minX...g.maxX {
                    if c.x+x>=sw || (p[(c.y+y)*sw+c.x+x] != inv) != (g.rows[y] & (1 << (g.width-x-1)) != 0) { same=false }
                } }
                for y in 0..<g.height { for x in 0..<min(g.width,sw-c.x) {
                    if x>=g.minX && x<=g.maxX && y>=g.minY && y<=g.maxY { continue }
                    if p[(c.y+y)*sw+c.x+x]==inv { continue }
                    var cursor=x<g.minX || x>g.maxX
                    if cursor { for j in 0..<g.height { if p[(c.y+j)*sw+c.x+x]==inv { cursor=false } } }
                    if !cursor && y==g.height-1 && y>g.maxY { cursor=(0..<min(g.width,sw-c.x)).allSatisfy { p[(c.y+y)*sw+c.x+$0] != inv } }
                    if !cursor { same=false }
                } }
                if same { let kept=Cell(x:c.x,y:c.y,inverse:inv,glyph:g); occupy(kept,&occupied,sw); result.append(kept); break }
            }
        }
        for c in fresh where !overlaps(c,occupied,sw) { occupy(c,&occupied,sw); result.append(c) }; return result
    }
    private func cached(_ key: String, _ rows: [Int], _ width: Int, _ ch: Int) -> Glyph {
        if let g=dynamic[key] { return g }
        let g=Glyph(1,width,rows.count,ch,rows,dynamic:true); dynamic[key]=g; return g
    }
    private func integrals(_ p: [Bool], _ sw: Int, _ sh: Int, _ occupied: inout [Bool], _ singles: [Cell], _ out: inout [Cell], _ retainedContext: Bool) {
        for y in 14..<sh-20 { for x in 0...sw-5 { for inv in [false,true] {
            if row(p,sw,x,y,5,inv) != 2 || row(p,sw,x,y+1,5,inv) != 5 { continue }
            var end=y+2; while end<sh-14 && row(p,sw,x,end,5,inv)==4 { end += 1 }
            if end<y+5 || row(p,sw,x,end,5,inv) != 20 || row(p,sw,x,end+1,5,inv) != 8 { continue }
            let h=end-y+2; var rows=Array(repeating:4,count:h); rows[0]=2; rows[1]=5; rows[h-2]=20; rows[h-1]=8
            let c=Cell(x:x,y:y,inverse:inv,glyph:cached("integral:\(h)",rows,5,Self.special(189)))
            if overlaps(c,occupied,sw) || (!inv && !border(c,p,sw,sh)) { continue }
            if !singles.contains(where:{$0.inverse==inv && $0.x>=x+5 && $0.x<=x+(retainedContext ? 60:20) && $0.y>=y && $0.y+$0.glyph.height<=y+h+1 && (retainedContext || border($0,p,sw,sh))}) { continue }
            occupy(c,&occupied,sw); out.append(c)
        } } }
    }
    private func parentheses(_ p: [Bool], _ sw: Int, _ sh: Int, _ occupied: inout [Bool], _ out: inout [Cell]) {
        var candidates:[Cell]=[]
        for y in 14..<sh-18 { for x in 0...sw-3 { for inv in [false,true] {
            let cap=row(p,sw,x,y,3,inv); if cap != 1 && cap != 4 { continue }
            let ch=cap==1 ? 40:41, stem=cap==1 ? 4:1
            if row(p,sw,x,y+1,3,inv) != 2 { continue }
            var end=y+2; while end<sh-14 && row(p,sw,x,end,3,inv)==stem { end += 1 }
            if end<y+5 || row(p,sw,x,end,3,inv) != 2 || row(p,sw,x,end+1,3,inv) != cap { continue }
            let h=end-y+2; var rows=Array(repeating:stem,count:h); rows[0]=cap; rows[1]=2; rows[h-2]=2; rows[h-1]=cap
            let c=Cell(x:x,y:y,inverse:inv,glyph:cached("\(ch):\(h)",rows,3,ch))
            if !overlaps(c,occupied,sw) && (inv || border(c,p,sw,sh)) && exact(c,p,sw) { candidates.append(c) }
        } } }
        for left in candidates where left.glyph.character==40 {
            guard let right=candidates.filter({$0.glyph.character==41 && $0.inverse==left.inverse && $0.y==left.y && $0.glyph.height==left.glyph.height && $0.x>left.x+3}).min(by:{$0.x<$1.x}) else { continue }
            if overlaps(left,occupied,sw) || overlaps(right,occupied,sw) { continue }
            if !out.contains(where:{anchor($0.glyph.character) && $0.inverse==left.inverse && $0.x>=left.x+3 && $0.x+$0.glyph.width<=right.x && $0.y>=left.y && $0.y+$0.glyph.height<=left.y+left.glyph.height+1}) { continue }
            occupy(left,&occupied,sw); occupy(right,&occupied,sw); out.append(left); out.append(right)
        }
    }
    private func dropdowns(_ p: [Bool], _ sw: Int, _ sh: Int, _ occupied: inout [Bool], _ out: inout [Cell]) {
        if sh<16 || !(0..<sw).allSatisfy({p[15*sw+$0]}) { return }
        var arrows:[Cell]=[]
        for f in out where f.glyph.font==0 && f.glyph.character==70 && f.y==2 {
            for n in out where n.glyph.font==0 && (49...56).contains(n.glyph.character) && n.y==f.y && n.x==f.x+f.glyph.width && n.inverse==f.inverse {
                let c=Cell(x:n.x+n.glyph.width,y:f.y+2,inverse:f.inverse,glyph:arrow)
                if c.x+3<=sw && !overlaps(c,occupied,sw) && !overlaps(c,blocked,sw) && exact(c,p,sw) { occupy(c,&occupied,sw); arrows.append(c) }
            }
        }; out.append(contentsOf:arrows)
    }
}
