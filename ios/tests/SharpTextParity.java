import java.nio.file.*;
import java.util.*;
import com.graph89.emulationcore.SharpTextRecognizer;
public final class SharpTextParity {
 static String dump(List<SharpTextRecognizer.Cell> cells) {
  ArrayList<String> rows=new ArrayList<>();
  for(var c:cells) {var g=c.glyph;rows.add(c.x+","+c.y+","+(c.inverse?1:0)+","+g.font+","+g.width+","+g.height+","+(int)g.character+","+(g.mathDelimiter?1:0));}
  Collections.sort(rows);return String.join(";",rows);
 }
 public static void main(String[] args)throws Exception {
  var r=new SharpTextRecognizer(Files.readAllBytes(Paths.get(args[0])));
  List<SharpTextRecognizer.Cell> previous=Collections.emptyList();
  for(int i=1;i<args.length;i++) {
   byte[] bytes=Files.readAllBytes(Paths.get(args[i]));boolean[] p=new boolean[bytes.length];for(int j=0;j<p.length;j++)p[j]=bytes[j]!=0;
   System.out.println("fresh:"+dump(r.recognize(p,160,100)));
   previous=r.recognizeStable(p,160,100,previous);System.out.println("stable:"+dump(previous));
  }
 }
}
