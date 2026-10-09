import com.graph89.emulationcore.SharpTextRecognizer;
import java.util.List;
public final class SmallLabelITest {
    private static final int W=160,H=100;
    private static void font(byte[] data,char c,int width,int...rows){int p=c*12;data[p]=(byte)width;data[p+1]=5;for(int y=0;y<5;y++)data[p+2+y]=(byte)(rows[y]<<(8-width));}
    private static int draw(byte[] fonts,boolean[] pixels,char c,int x,int y,boolean inverse){int p=c*12,width=fonts[p];for(int j=0;j<5;j++)for(int i=0;i<width;i++)pixels[(y+j)*W+x+i]=((fonts[p+2+j]&(128>>i))!=0)!=inverse;return x+width;}
    private static boolean hasI(List<SharpTextRecognizer.Cell> cells){for(SharpTextRecognizer.Cell c:cells)if(c.glyph.font==0&&c.glyph.character=='I')return true;return false;}
    private static void check(boolean ok,String message){if(!ok)throw new AssertionError(message);}
    public static void main(String[]args){
        byte[] f=new byte[3*256*12];font(f,'M',4,10,14,10,10,10);font(f,'A',4,4,10,14,10,10);font(f,'I',2,2,2,2,2,2);font(f,'|',2,2,2,2,2,2);font(f,'N',4,10,14,14,10,10);
        SharpTextRecognizer r=new SharpTextRecognizer(f);
        for(boolean inverse:new boolean[]{false,true}){boolean[] p=new boolean[W*H];java.util.Arrays.fill(p,inverse);int x=10;for(char c:"MAIN".toCharArray())x=draw(f,p,c,x,95,inverse);List<SharpTextRecognizer.Cell> cells=r.recognize(p,W,H);check(hasI(cells),"MAIN must contain sharp I in both polarities");
            for(int y=95;y<100;y++)for(int i=10;i<18;i++)p[y*W+i]=inverse;for(int y=95;y<100;y++)for(int i=20;i<24;i++)p[y*W+i]=inverse;
            List<SharpTextRecognizer.Cell> next=r.recognizeStable(p,W,H,cells);check(!hasI(next),"Cached I must lose word context when neighbours clear");}
        boolean[] p=new boolean[W*H];draw(f,p,'I',18,95,false);check(!hasI(r.recognize(p,W,H)),"Isolated vertical bar stays original");
        p=new boolean[W*H];int x=10;for(char c:"MAIN".toCharArray())x=draw(f,p,c,x,40,false);check(!hasI(r.recognize(p,W,H)),"Ambiguous bars in the body stay original");
        p=new boolean[W*H];draw(f,p,'A',10,95,false);draw(f,p,'I',16,95,false);draw(f,p,'N',20,95,false);check(!hasI(r.recognize(p,W,H)),"Separated bar is not part of a word");
        p=new boolean[W*H];int end=draw(f,p,'M',10,95,false);end=draw(f,p,'A',end,95,false);draw(f,p,'I',end,95,false);for(int y=90;y<100;y++)p[y*W+end]=true;
        check(!hasI(r.recognize(p,W,H)),"A continuing box divider beside a word stays pixels");
        System.out.println("Small I: word context, inversion, isolated bars, body exclusion and cached-context loss passed.");
    }
}
