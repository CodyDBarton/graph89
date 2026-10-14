import com.graph89.emulationcore.SharpTextRecognizer;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
public final class RetainedTextParity {
    public static void main(String[] args) throws Exception {
        SharpTextRecognizer r=new SharpTextRecognizer(Files.readAllBytes(Paths.get(args[0])));
        List<SharpTextRecognizer.Cell> previous=Collections.emptyList();
        List<String> bases=new ArrayList<String>();
        for(int i=1;i<args.length;i++) {
            if(args[i].startsWith("@"))bases.addAll(Files.readAllLines(Paths.get(args[i].substring(1))));
            else bases.add(args[i]);
        }
        for(String base:bases) {
            byte[] b=Files.readAllBytes(Paths.get(base+".pixels"));boolean[] p=new boolean[b.length];
            for(int j=0;j<b.length;j++)p[j]=b[j]!=0;
            String s=new String(Files.readAllBytes(Paths.get(base+".packets")),"UTF-8").trim();
            String[] v=s.length()==0?new String[0]:s.split("\\s+");int[] packets=new int[v.length];
            for(int j=0;j<v.length;j++)packets[j]=Integer.parseInt(v[j]);
            p=SharpTextRecognizer.withoutCursor(p,packets);
            previous=r.recognizeStable(p,160,100,previous);
            List<String> result=new ArrayList<String>();
            for(SharpTextRecognizer.Cell c:r.retained(packets,previous)) {
                SharpTextRecognizer.Glyph g=c.glyph;
                result.add(c.x+","+c.y+","+g.font+","+(int)g.character+","+(c.inverse?1:0)+","+g.width+","+g.height+","+(c.shaded?1:0));
            }
            Collections.sort(result);System.out.println(String.join(";",result));
        }
    }
}
