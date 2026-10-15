import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
@main struct Analyze {
 static func main() throws {
  let a=CommandLine.arguments,dir=URL(fileURLWithPath:a[1]),out=URL(fileURLWithPath:a[2]);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  let r=SharpTextRecognizer(Array(try Data(contentsOf:dir.appendingPathComponent("fonts.bin"))))
  let fontURL=URL(fileURLWithPath:a[3]);let descriptors=CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as! [CTFontDescriptor]
  let font=CTFontCreateWithFontDescriptor(descriptors[0],2048,nil)
  func glyphPath(_ c:Int)->CGPath?{var ch=UniChar(c),g:CGGlyph=0;guard CTFontGetGlyphsForCharacters(font,&ch,&g,1),g != 0 else{return nil};return CTFontCreatePathForGlyph(font,g,nil)}
  var family=CGRect.null;for c in 33..<127{if let p=glyphPath(c){family=family.union(p.boundingBoxOfPath)}}
  let plotGlyphs=(0..<128).map {SharpTextRecognizer.Glyph(1,6,8,$0,Array(repeating:0,count:8))}
  var paths:[ObjectIdentifier:CGPath]=[:]
  func outline(_ g:SharpTextRecognizer.Glyph)->CGPath? {
   let id=ObjectIdentifier(g);if let p=paths[id]{return p}
   if g.character==SharpTextRecognizer.dropdown {let p=CGMutablePath();p.move(to:.zero);p.addLine(to:CGPoint(x:3,y:0));p.addLine(to:CGPoint(x:1.5,y:2));p.closeSubpath();paths[id]=p;return p}
   if g.character==SharpTextRecognizer.special(18) {let p=CGMutablePath();p.move(to:CGPoint(x:g.minX,y:g.minY));p.addLine(to:CGPoint(x:Double(g.maxX+1),y:Double(g.minY+g.maxY+1)/2));p.addLine(to:CGPoint(x:g.minX,y:g.maxY+1));p.closeSubpath();paths[id]=p;return p}
   if SharpTextRecognizer.sizedSymbol(g.character-0xe100),(0...2).contains(g.font),let p=glyphPath(0xe400+g.font*256+g.character-0xe100){var m=CGAffineTransform(a:1/200.0,b:0,c:0,d:-1/200.0,tx:0,ty:10);let path=p.copy(using:&m);paths[id]=path;return path}
   if g.character==SharpTextRecognizer.special(180),let p=glyphPath(0xe300+g.font){var m=CGAffineTransform(a:1/200.0,b:0,c:0,d:-1/200.0,tx:0,ty:10);let path=p.copy(using:&m);paths[id]=path;return path}
   guard let p=glyphPath(g.character) else{return nil};let b=p.boundingBoxOfPath
   var scale=(CGFloat(g.height)-0.1)/family.height;if b.width>0{scale=min(scale,(CGFloat(g.width)-0.1)/b.width)}
   var ch=UniChar(g.character),glyph:CGGlyph=0,advance=CGSize.zero;CTFontGetGlyphsForCharacters(font,&ch,&glyph,1);CTFontGetAdvancesForGlyphs(font,.horizontal,&glyph,&advance,1)
   var m=g.dynamic && !b.isEmpty ? CGAffineTransform(a:(CGFloat(g.width)-0.1)/b.width,b:0,c:0,d:-(CGFloat(g.height)-0.1)/b.height,tx:0.05-b.minX*(CGFloat(g.width)-0.1)/b.width,ty:0.05+b.maxY*(CGFloat(g.height)-0.1)/b.height):CGAffineTransform(a:scale,b:0,c:0,d:-scale,tx:(CGFloat(g.width)-advance.width*scale)/2,ty:0.05+family.maxY*scale)
   let path=p.copy(using:&m);paths[id]=path;return path
  }
  func drawPlot(_ context:CGContext,_ plot:[Float],_ plotBackground:[UInt8],_ plotDecorations:[Float],_ pixels:[Bool]) {
        guard plot.count>6,plotBackground.count==16000 else {return}
        context.saveGState()
        context.clip(to:CGRect(x:CGFloat(plot[0]),y:CGFloat(plot[1]),width:CGFloat(plot[2]-plot[0]),height:CGFloat(plot[3]-plot[1])))
        // Preserve native interaction overlays already drawn with sharp text.
        let visible=CGMutablePath()
        visible.addRect(CGRect(x:CGFloat(plot[0]),y:CGFloat(plot[1]),width:CGFloat(plot[2]-plot[0]),height:CGFloat(plot[3]-plot[1])))
        for y in 16..<93 {var x=0;while x<159 {
            if plotBackground[y*160+x]&2==0 {x += 1;continue}
            let left=x;while x<159 && plotBackground[y*160+x]&2 != 0 {x += 1}
            visible.addRect(CGRect(x:left,y:y,width:x-left,height:1))
        }}
        context.addPath(visible);context.clip(using:.evenOdd)
        context.setFillColor(CGColor(gray:210/255.0,alpha:1));context.fill(CGRect(x:0,y:16,width:159,height:77))
        let axes=CGMutablePath()
        for y in 16..<93 {var x=0;while x<159 {
            if plotBackground[y*160+x]&1==0 {x += 1;continue}
            let left=x;while x<159 && plotBackground[y*160+x]&1 != 0 {x += 1}
            axes.addRect(CGRect(x:left,y:y,width:x-left,height:1))
        }}
        context.setFillColor(CGColor(gray:30/255.0,alpha:1));context.addPath(axes);context.fillPath()
        context.setStrokeColor(CGColor(gray:30/255.0,alpha:1))
        context.setLineWidth(240/(960));context.setLineCap(.round)
        let geometry=CGMutablePath()
        for i in stride(from:0,to:plotDecorations.count,by:4) {
            if plotDecorations[i].isNaN {
                let kind=plotDecorations[i+1],x=CGFloat(plotDecorations[i+2]),y=CGFloat(plotDecorations[i+3])
                if kind == -5 || kind == -6 {
                    context.setFillColor(CGColor(gray:30/255.0,alpha:1))
                    if kind == -6 {context.fill(CGRect(x:x-1.5,y:y-1.5,width:3,height:3))}
                    else {context.fillEllipse(in:CGRect(x:x-1,y:y-1,width:2,height:2))}
                }
                continue
            }
            let p=CGPoint(x:CGFloat(plotDecorations[i]),y:CGFloat(plotDecorations[i+1]))
            let q=CGPoint(x:CGFloat(plotDecorations[i+2]),y:CGFloat(plotDecorations[i+3]))
            if p==q {let radius:CGFloat=120/960;context.fillEllipse(in:CGRect(x:p.x-radius,y:p.y-radius,width:2*radius,height:2*radius))}
            else {geometry.move(to:p);geometry.addLine(to:q)}
        }
        context.addPath(geometry);context.strokePath()
        let surface=stride(from:0,to:plotDecorations.count,by:4).contains {plotDecorations[$0].isNaN && plotDecorations[$0+1] == -7 && plotDecorations[$0+2] == 5}
        let path=CGMutablePath();var previous:CGPoint?
        for i in stride(from:4,to:plot.count-1,by:2) {
            let point=CGPoint(x:CGFloat(plot[i])+0.5,y:CGFloat(plot[i+1])+0.5)
            guard point.x.isFinite,point.y.isFinite else {previous=nil;continue}
            if let p=previous, surface || !((p.y<16 && point.y>93)||(p.y>93 && point.y<16)) {
                // Clip before building the graphics path. Values near poles can
                // be enormous; they must never reach the device rasterizer.
                let dx=point.x-p.x,dy=point.y-p.y
                var lo:CGFloat=0,hi:CGFloat=1,valid=true
                for (d,q) in [(-dx,p.x-CGFloat(plot[0])),(dx,CGFloat(plot[2])-p.x),(-dy,p.y-CGFloat(plot[1])),(dy,CGFloat(plot[3])-p.y)] {
                    if d==0 {if q<0 {valid=false};continue}
                    let t=q/d
                    if d<0 {lo=max(lo,t)} else {hi=min(hi,t)}
                }
                if valid && lo<=hi {
                    path.move(to:CGPoint(x:p.x+lo*dx,y:p.y+lo*dy))
                    path.addLine(to:CGPoint(x:p.x+hi*dx,y:p.y+hi*dy))
                }
            }
            previous=point
        }
        context.setStrokeColor(CGColor(gray:30/255.0,alpha:1))
        context.setLineWidth(240/(960));context.setLineJoin(.round);context.setLineCap(.round)
        context.addPath(path);context.strokePath();context.restoreGState()
        context.saveGState()
        context.clip(to:CGRect(x:CGFloat(plot[0]),y:CGFloat(plot[1]),width:CGFloat(plot[2]-plot[0]),height:CGFloat(plot[3]-plot[1])))
        var vectorCursor=false
        for i in stride(from:0,to:plotDecorations.count,by:4) where plotDecorations[i].isNaN {
            let kind=Int(plotDecorations[i+1]),x=CGFloat(plotDecorations[i+2]),y=CGFloat(plotDecorations[i+3])
            if kind == -2 || kind == -4 {vectorCursor=true}
            else if kind == -1 || kind == -3 {
                vectorCursor=true
                context.saveGState();context.clip(to:CGRect(x:0,y:16,width:159,height:67))
                let radius:CGFloat=kind == -3 ? 7.5:3,extent:CGFloat=kind == -3 ? 10:5
                let cursor=CGMutablePath();cursor.addEllipse(in:CGRect(x:x-radius,y:y-radius,width:2*radius,height:2*radius))
                cursor.move(to:CGPoint(x:x-extent,y:y));cursor.addLine(to:CGPoint(x:x+extent,y:y))
                cursor.move(to:CGPoint(x:x,y:y-extent));cursor.addLine(to:CGPoint(x:x,y:y+extent))
                context.setLineCap(.butt)
                context.setStrokeColor(CGColor(gray:210/255.0,alpha:1));context.setLineWidth(2);context.addPath(cursor);context.strokePath()
                context.setStrokeColor(CGColor(gray:30/255.0,alpha:1));context.setLineWidth(0.8);context.addPath(cursor);context.strokePath();context.restoreGState()
            } else if (48...57).contains(kind) || (120...122).contains(kind) {
                let glyph=plotGlyphs[kind]
                if let path=outline(glyph) {
                    context.saveGState();context.translateBy(x:x,y:y);context.clip(to:CGRect(x:0,y:0,width:6,height:8))
                    context.setFillColor(CGColor(gray:210/255.0,alpha:1));context.fill(CGRect(x:0,y:0,width:6,height:8))
                    context.setFillColor(CGColor(gray:30/255.0,alpha:1));context.addPath(path);context.fillPath();context.restoreGState()
                }
            }
        }
        if !vectorCursor {
            for y in 16..<83 { for x in 0..<159 where plotBackground[y*160+x]&4 != 0 {
                context.setFillColor(CGColor(gray:(pixels[y*160+x] ? 30:210)/255.0,alpha:1))
                context.fill(CGRect(x:x,y:y,width:1,height:1))
            } }
        }
        context.restoreGState()
    }
  func render(_ pixels:[Bool],_ cells:[SharpTextRecognizer.Cell],_ url:URL,_ native:URL,_ packets:[Int32]){
   var plot:[Float]=[],background:[UInt8]=[],decorations:[Float]=[]
   if let data=try? Data(contentsOf:native),data.count>=16008 {
    let np=Int(data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:0,as:Int32.self)}),nd=Int(data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:4,as:Int32.self)})
    if np>=0,nd>=0,data.count==16008+(np+nd)*4 {background=Array(data[8..<16008]);plot=(0..<np).map{i in data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:16008+i*4,as:Float.self)}};decorations=(0..<nd).map{i in data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:16008+(np+i)*4,as:Float.self)}}}
   }
   func nativeCursor(_ c:SharpTextRecognizer.Cell)->Bool {
    guard background.count==16000,c.y<83,c.y+c.glyph.height>16 else{return false}
    return (max(16,c.y)..<min(83,c.y+c.glyph.height)).contains{y in (max(0,c.x)..<min(159,c.x+c.glyph.width)).contains{x in background[y*160+x]&4 != 0}}
   }

   let scene=a.contains("--compact") ? r.compactScene(packets):nil
   func drawCompact(_ scene:SharpTextRecognizer.CompactScene,_ context:CGContext) {
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
            context.setFillColor(CGColor(gray:30/255.0,alpha:1))
            context.addPath(raster);context.fillPath()
        } else if scene.body && !scene.repackedHistory {
            context.setFillColor(CGColor(gray:30/255.0,alpha:1))
            let markers=CGMutablePath()
            for x in 0..<6 {
                var y=16
                while y<83 {
                    if !pixels[y*160+x] { y += 1;continue }
                    let top=y
                    while y<83 && pixels[y*160+x] { y += 1 }
                    markers.addRect(CGRect(x:Double(x),y:83+Double(top-83)*0.72+scene.markerOffsets[(top+y)/2-16],width:1,height:Double(y-top)*0.72))
                }
            }
            context.addPath(markers);context.fillPath()
        }
        context.saveGState();context.clip(to:CGRect(x:0,y:scene.yEditor ? 21.04:16,width:160,height:scene.yEditor ? 61.96:67))
        context.setFillColor(CGColor(gray:30/255.0,alpha:1))
        for r in scene.inverseRects { context.fill(CGRect(x:r[0],y:r[1],width:r[2],height:r[3])) }
        context.restoreGState()
        for item in scene.items where item.inverse && item.glyph != nil && item.scale==0.8 {
            let g=item.glyph!
            context.saveGState();context.clip(to:CGRect(x:0,y:item.y>=84 ? 84:16,width:160,height:item.y>=84 ? 9:67))
            context.setFillColor(CGColor(gray:30/255.0,alpha:1))
            context.fill(CGRect(x:item.selectionX ?? item.x-0.5,y:item.y,width:item.advance,height:Double(g.height)*item.scale))
            context.restoreGState()
        }
        for item in scene.items {
            context.saveGState()
            context.clip(to:CGRect(x:0,y:item.scale==0.8 ? 84:item.clipTop,width:160,height:item.scale==0.8 ? 9:83-item.clipTop))
            let color=CGColor(gray:(item.inverse ? 210:30)/255.0,alpha:1)
            context.setFillColor(color);context.setStrokeColor(color)
            if let g=item.glyph {
                context.translateBy(x:item.x,y:item.y);context.scaleBy(x:item.scale,y:item.scale*item.heightScale)
                if g.character != 0,let path=outline(g) { context.addPath(path);context.fillPath() }
                else {
                    // Fill the complete bitmap in one pass so adjoining scaled
                    // pixels do not acquire antialiased seams (history markers).
                    let bitmap=CGMutablePath()
                    for y in 0..<g.height { for x in 0..<g.width where g.rows[y]&(1<<(g.width-x-1)) != 0 { bitmap.addRect(CGRect(x:x,y:y,width:1,height:1)) } }
                    context.addPath(bitmap);context.fillPath()
                }
            } else if item.attribute != 0 {
                context.setLineWidth(item.scale)
                context.setLineCap(.square)
                context.move(to:CGPoint(x:item.x+item.scale/2,y:item.y+item.scale/2))
                context.addLine(to:CGPoint(x:item.x1+item.scale/2,y:item.y1+item.scale/2));context.strokePath()
                if item.x==item.x1 && item.y==item.y1 { context.fill(CGRect(x:item.x,y:item.y,width:item.scale,height:item.scale)) }
            }
            context.restoreGState()
        }
        if let x=scene.cursorX,let cursor=SharpTextRecognizer.cursor(packets) {
            context.setFillColor(CGColor(gray:30/255.0,alpha:1))
            for y in 0..<8 where cursor.mask&(1<<y) != 0 { context.fill(CGRect(x:x,y:85.8+Double(y)*0.8,width:0.6,height:0.8)) }
        }
        context.restoreGState()
    }
   let ctx=CGContext(data:nil,width:960,height:600,bitsPerComponent:8,bytesPerRow:3840,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
   ctx.translateBy(x:0,y:600);ctx.scaleBy(x:6,y:-6)
   var cleaned=pixels
   if scene?.body==true {for y in 16..<83 {for x in 0..<160 {cleaned[y*160+x]=false}}}
   if scene?.input==true {for y in 84..<93 {for x in 0..<160 {cleaned[y*160+x]=false}}}
   func skip(_ c:SharpTextRecognizer.Cell)->Bool {
    nativeCursor(c) || (scene?.body==true && c.y<83 && c.y+c.glyph.height>16) || (scene?.input==true && c.y==85)
   }
   for c in cells where !skip(c) {let g=c.glyph;for y in g.minY...g.maxY{for x in g.minX...g.maxX where c.x+x>=c.clipLeft && c.x+x<c.clipRight && c.y+y>=c.clipTop && c.y+y<c.clipBottom{cleaned[(c.y+y)*160+c.x+x]=c.inverse}}}
   ctx.setFillColor(CGColor(gray:210/255.0,alpha:1));ctx.fill(CGRect(x:0,y:0,width:160,height:100));ctx.setFillColor(CGColor(gray:30/255.0,alpha:1))
   let bitmap=CGMutablePath();for y in 0..<100 {for x in 0..<160 where cleaned[y*160+x]{bitmap.addRect(CGRect(x:x,y:y,width:1,height:1))}};ctx.addPath(bitmap);ctx.fillPath()
   for c in cells where !skip(c) {let g=c.glyph;guard g.character != 0,let path=outline(g) else{continue};ctx.saveGState();ctx.clip(to:CGRect(x:c.clipLeft,y:c.clipTop,width:c.clipRight-c.clipLeft,height:c.clipBottom-c.clipTop));ctx.translateBy(x:CGFloat(c.x),y:CGFloat(c.y));let clip=CGMutablePath();clip.addRect(CGRect(x:0,y:0,width:g.width,height:g.height));for y in max(0,c.clipTop-c.y)..<min(g.height,c.clipBottom-c.y){for x in max(0,c.clipLeft-c.x)..<min(g.width,c.clipRight-c.x){if x>=g.minX&&x<=g.maxX&&y>=g.minY&&y<=g.maxY{continue};if pixels[(c.y+y)*160+c.x+x] != c.inverse{clip.addRect(CGRect(x:x,y:y,width:1,height:1))}}};ctx.addPath(clip);ctx.clip(using:.evenOdd);ctx.setFillColor(CGColor(gray:(c.shaded ? 120:(c.inverse ? 210:30))/255.0,alpha:1));ctx.addPath(path);ctx.fillPath();ctx.restoreGState()}
   if let scene {drawCompact(scene,ctx)}
   drawPlot(ctx,plot,background,decorations,pixels)
   let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!;CGImageDestinationAddImage(dest,ctx.makeImage()!,nil);CGImageDestinationFinalize(dest)
  }
  let files=try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).filter{$0.pathExtension=="pgm"}.sorted{$0.lastPathComponent<$1.lastPathComponent}
  var previous:[SharpTextRecognizer.Cell]=[],report:[[String:Any]]=[]
  var pendingFrames=0,clashes=0,unsupportedFrames=0,missingOutlines=0
  for (i,file) in files.enumerated(){
   let base=file.deletingPathExtension();let raw=Array(try Data(contentsOf:file).suffix(16000));let packets=(try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathExtension("cells.json"))) as! [[Int]]).flatMap{$0}.map{Int32($0)}
   let pending=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathExtension("pending.json"))) as! [[Int]]
   let pixels=SharpTextRecognizer.withoutCursor(raw.map{$0==30},packets);previous=r.stable(pixels,previous);let cells=r.retained(packets,fallback:previous)
   let records=stride(from:0,to:packets.count,by:12).filter{(0...3).contains(packets[$0+2])}
   func isDirect(_ c:SharpTextRecognizer.Cell)->Bool{records.contains{j in Int(packets[j])==c.x && Int(packets[j+1])==c.y && c.glyph.character==(packets[j+3]>=33&&packets[j+3]<127 ? Int(packets[j+3]):SharpTextRecognizer.special(Int(packets[j+3]))) && Int(packets[j+6])==c.glyph.height}}
   let suspects=cells.filter{c in !isDirect(c) && pending.contains{p in c.x<p[0]+p[2]&&c.x+c.glyph.width>p[0]&&c.y<p[1]+p[3]&&c.y+c.glyph.height>p[1]}}
   let unsupported=records.filter{j in !(33..<127).contains(packets[j+3]) && packets[j+3] != 32 && SharpTextRecognizer.special(Int(packets[j+3]))==0}
   let missing=cells.filter{outline($0.glyph)==nil}
   let overlap=cells.enumerated().filter{idx,c in cells.dropFirst(idx+1).contains{d in max(c.x,c.clipLeft)<min(d.x+d.glyph.width,d.clipRight)&&max(d.x,d.clipLeft)<min(c.x+c.glyph.width,c.clipRight)&&max(c.y,c.clipTop)<min(d.y+d.glyph.height,d.clipBottom)&&max(d.y,d.clipTop)<min(c.y+c.glyph.height,c.clipBottom)}}
   if !suspects.isEmpty{pendingFrames+=1};if !overlap.isEmpty{clashes+=1};if !unsupported.isEmpty{unsupportedFrames+=1};missingOutlines+=missing.count
   if !suspects.isEmpty || !overlap.isEmpty || !missing.isEmpty || i%65==0 || i==files.count-1 || a.contains("--all") {
    let entry:[String:Any]=["frame":file.lastPathComponent,"pendingFallback":suspects.map{[$0.x,$0.y,$0.glyph.font,$0.glyph.character,$0.glyph.width,$0.glyph.height]},"overlaps":overlap.count,"missingOutline":missing.count,"missingGlyphs":missing.map{[$0.glyph.font,$0.glyph.character]},"unsupported":unsupported.map{Int(packets[$0+3])},"cells":cells.count]
    report.append(entry)
    if report.count<=160 || i%65==0 {render(pixels,cells,out.appendingPathComponent(base.lastPathComponent+".png"),base.appendingPathExtension("hdplot"),packets)}
   }
   if i%250==0{print("Analyzed \(i)/\(files.count)");fflush(stdout)}
  }
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("candidates.json"))
  let summary:[String:Any]=["frames":files.count,"pendingFallbackFrames":pendingFrames,"overlapFrames":clashes,"unsupportedFrames":unsupportedFrames,"missingOutlineCells":missingOutlines]
  try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("summary.json"));print(summary)
 }
}
