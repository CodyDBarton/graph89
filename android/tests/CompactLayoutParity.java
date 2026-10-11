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
            items.add((scene.body?1:0)+","+(scene.input?1:0)+","+scene.inputStart+","+scene.inputCount+","+scene.fullInputCount+","+(scene.cursorX==null?-1:Math.round(scene.cursorX*1000)));
            for(SharpTextRecognizer.CompactItem item:scene.items) {
                SharpTextRecognizer.Glyph g=item.glyph;
                items.add(Math.round(item.x*1000)+","+Math.round(item.y*1000)+","+Math.round(item.scale*1000)+","+(item.inverse?1:0)+","+(g==null?-1:(int)g.character)+","+(g==null?Math.round(item.x1*1000):g.width)+","+(g==null?Math.round(item.y1*1000):g.height));
            }
            System.out.println(String.join(";",items));
        }
    }
}
