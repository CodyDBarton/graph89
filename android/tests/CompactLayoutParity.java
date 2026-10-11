import com.graph89.emulationcore.SharpTextRecognizer;
import java.nio.file.*;
import java.util.*;
public final class CompactLayoutParity {
    public static void main(String[] args) throws Exception {
        SharpTextRecognizer r=new SharpTextRecognizer(Files.readAllBytes(Paths.get(args[0])));
        for(String base:Arrays.copyOfRange(args,1,args.length)) {
            String s=new String(Files.readAllBytes(Paths.get(base+".packets")),"UTF-8").trim();
            String[] words=s.isEmpty()?new String[0]:s.split("\\s+");int[] packets=new int[words.length];
            for(int i=0;i<words.length;i++)packets[i]=Integer.parseInt(words[i]);
            SharpTextRecognizer.CompactScene scene=r.compactScene(packets);
            List<String> items=new ArrayList<String>();
            long rectHeight=0,markerOffset=0;for(double[] rect:scene.inverseRects)rectHeight+=Math.round(rect[3]*1000);for(double offset:scene.markerOffsets)markerOffset+=Math.round(offset*1000);
            items.add((scene.body?1:0)+","+(scene.input?1:0)+","+scene.inputStart+","+scene.inputCount+","+scene.fullInputCount+","+(scene.cursorX==null?-1:Math.round(scene.cursorX*1000))+","+scene.inverseRects.size()+","+rectHeight+","+markerOffset+","+Math.round(scene.verticalSaved*1000)+","+(scene.repackedHistory?1:0)+","+scene.visibleHistoryEntries+","+Math.round(scene.historySaved*1000));
            for(SharpTextRecognizer.CompactItem item:scene.items) {
                SharpTextRecognizer.Glyph g=item.glyph;
                items.add(Math.round(item.x*1000)+","+Math.round(item.y*1000)+","+Math.round(item.scale*1000)+","+(item.inverse?1:0)+","+(g==null?-1:(int)g.character)+","+(g==null?Math.round(item.x1*1000):g.width)+","+(g==null?Math.round(item.y1*1000):g.height)+","+Math.round(item.advance*1000)+","+(item.selectionX==null?-1:Math.round(item.selectionX*1000))+","+Math.round(item.heightScale*1000));
            }
            System.out.println(String.join(";",items));
        }
    }
}
