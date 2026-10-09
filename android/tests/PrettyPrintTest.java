import com.graph89.emulationcore.SharpTextRecognizer;
import java.util.List;

/** Synthetic mixed-baseline expressions; no ROM or Android runtime required. */
public final class PrettyPrintTest {
    private static final int W = 160, H = 100;
    private static final byte[] FONTS = new byte[3 * 256 * 12];
    private static final int[] TWO = {28,34,2,4,8,16,62,0};
    private static final int[] X = {0,0,34,20,8,20,34,0};
    private static final int[] THREE = {12,2,4,2,12};
    private static void font(int f, char c, int w, int[] rows) {
        int p = (f * 256 + c) * 12;
        FONTS[p] = (byte)w; FONTS[p+1] = (byte)rows.length;
        for (int y = 0; y < rows.length; ++y) FONTS[p+2+y] = (byte)(rows[y] << (8-w));
    }
    private static void draw(boolean[] pixels, int x, int y, int w, int[] rows) {
        for (int j = 0; j < rows.length; ++j) for (int i = 0; i < w; ++i)
            pixels[(y+j)*W+x+i] = (rows[j] & (1 << (w-i-1))) != 0;
    }
    private static boolean[] home(String title) {
        boolean[] p = new boolean[W*H];
        for (int i = 0; i < title.length(); ++i) {
            int off = (256 + title.charAt(i))*12;
            int[] rows = new int[8];
            for (int y=0;y<8;++y) rows[y]=(FONTS[off+2+y]&255)>>>2;
            draw(p, 2+i*6, 2, 6, rows);
        }
        return p;
    }
    private static void paren(boolean[] p, int x, int y, int h, boolean closing) {
        int[] rows = new int[h];
        rows[0]=rows[h-1]=closing?4:1;
        rows[1]=rows[h-2]=2;
        for (int j=2;j<h-2;++j) rows[j]=closing?1:4;
        draw(p,x,y,3,rows);
    }
    private static boolean has(List<SharpTextRecognizer.Cell> cells, char c, int x, int y) {
        for (SharpTextRecognizer.Cell cell:cells)
            if (cell.glyph.character==c && cell.x==x && cell.y==y) return true;
        return false;
    }
    private static int delimiters(List<SharpTextRecognizer.Cell> cells) {
        int n=0; for (SharpTextRecognizer.Cell c:cells) if(c.glyph.mathDelimiter) ++n; return n;
    }
    private static void check(boolean ok, String why) { if(!ok) throw new AssertionError(why); }
    public static void main(String[] args) {
        // Distinct invented letter bitmaps let the recognizer identify a Home
        // or Graph toolbar without copying any firmware font data.
        String labels="AlgebraZoom";
        for (int i=0;i<labels.length();++i) {
            char c=labels.charAt(i);
            font(1,c,6,new int[]{30,34,(c&31)<<1,((c>>>5)+1)<<1,34,34,30,0});
        }
        font(1,'2',6,TWO); font(1,'x',6,X); font(0,'3',4,THREE);
        SharpTextRecognizer r=new SharpTextRecognizer(FONTS);
        boolean[] p=home("Algebra");
        paren(p,29,40,12,false); paren(p,47,40,12,true);
        draw(p,34,44,6,X); draw(p,41,40,6,TWO);
        List<SharpTextRecognizer.Cell> cs=r.recognize(p,W,H);
        check(has(cs,'2',41,40),"Raised digit beside parenthesis cap");
        check(has(cs,'(',29,40)&&has(cs,')',47,40),"Tall parentheses recognized as a pair");
        check(delimiters(cs)==2,"No partial-parenthesis letters");
        // A smaller exponent at a second level and an outer, taller pair.
        paren(p,24,35,22,false); paren(p,57,35,22,true);
        draw(p,51,35,4,THREE);
        cs=r.recognize(p,W,H);
        check(has(cs,'3',51,35),"Small-font isolated superscript");
        check(delimiters(cs)==4,"Nested parentheses at different heights");
        List<SharpTextRecognizer.Cell> previous=cs;
        paren(p,47,40,12,true); p[40*W+47]=false;
        cs=r.recognizeStable(p,W,H,previous);
        check(!has(cs,'(',29,40)&&!has(cs,')',47,40),"Changed pair loses both delimiter overlays immediately");
        check(has(cs,'2',41,40),"Unchanged exponent survives delimiter edit");
        p=home("Algebra"); paren(p,29,40,12,false); draw(p,34,44,6,X);
        check(delimiters(r.recognize(p,W,H))==0,"Unpaired graphic stays original");
        p=home("Algebra"); paren(p,29,40,12,false); paren(p,47,40,12,true);
        check(delimiters(r.recognize(p,W,H))==0,"Empty curves stay original");
        p=home("Algebra"); draw(p,41,40,6,TWO); p[39*W+43]=true;
        check(!has(r.recognize(p,W,H),'2',41,40),"Digit joined to graphics stays original");
        p=home("Zoom"); paren(p,29,40,12,false); paren(p,47,40,12,true);
        draw(p,34,44,6,X); draw(p,41,40,6,TWO);
        cs=r.recognize(p,W,H);
        check(!has(cs,'2',41,40)&&delimiters(cs)==0,"Graph plotting area remains original");
        check(r.recognizeStable(new boolean[W*H],W,H,previous).isEmpty(),"Clearing removes pretty-print overlays");
        // The Home input editor accepts punctuation on its fixed medium-font
        // grid in both polarities, without interpreting smaller fragments.
        int[] caret={0,8,20,34,0,0,0,0};
        int[] opening={8,16,32,32,32,16,8,0};
        int[] closing={16,8,4,4,4,8,16,0};
        font(1,'^',6,caret); font(1,'(',6,opening); font(1,')',6,closing);
        int[] tinyI={2,0,2,2,2},tinyD={12,10,10,10,12};
        font(0,'i',2,tinyI);font(0,'D',4,tinyD);
        r=new SharpTextRecognizer(FONTS); p=home("Algebra");
        for(int x=0;x<W;++x) {p[83*W+x]=true;p[93*W+x]=true;}
        // Invented unsupported symbol containing a false small-font i/D run.
        draw(p,1,86,2,tinyI);draw(p,3,86,4,tinyD);
        draw(p,7,85,6,caret);draw(p,13,85,6,opening);
        draw(p,19,85,6,TWO);draw(p,25,85,6,closing);
        cs=r.recognize(p,W,H);
        check(has(cs,'^',7,85)&&has(cs,'(',13,85)&&has(cs,')',25,85),"Normal input punctuation needs no word run");
        for(SharpTextRecognizer.Cell c:cs) if(c.y>=85&&c.y<93)
            check(c.glyph.font==1&&c.y==85&&(c.x-1)%6==0,"Reject off-grid input fragments");
        previous=cs;boolean[] selected=p.clone();
        for(int y=84;y<=92;++y) for(int x=0;x<31;++x) selected[y*W+x]=!selected[y*W+x];
        cs=r.recognizeStable(selected,W,H,previous);
        check(has(cs,'^',7,85)&&has(cs,'(',13,85)&&has(cs,')',25,85),"Inverse input punctuation");
        for(SharpTextRecognizer.Cell c:cs) if(c.y>=85&&c.y<93)
            check(c.glyph.font==1&&c.y==85&&c.inverse,"Inverse input has no small normal/inverse fragments");
        // The cursor covers the closing parenthesis's final blank column.
        previous=r.recognize(p,W,H);
        for(int y=85;y<93;++y){p[y*W+30]=true;p[y*W+31]=true;}
        cs=r.recognizeStable(p,W,H,previous);
        check(has(cs,')',25,85),"Reacquire parenthesis with trailing cursor");
        for(int y=84;y<=92;++y) for(int x=0;x<W;++x) p[y*W+x]=false;
        cs=r.recognizeStable(p,W,H,cs);
        for(SharpTextRecognizer.Cell c:cs) check(c.y<85||c.y>=93,"Cleared editor has no cached punctuation");
        int approvedCount=0;
        for(int code=0;code<256;++code) {
            char mapped=SharpTextRecognizer.specialCharacter(code);
            if(mapped==0) continue;
            ++approvedCount;
            int[] symbol={62,(code&31)<<1,((code>>>5)+1)<<1,34,42,34,62,0};
            font(1,(char)code,6,symbol);
            SharpTextRecognizer special=new SharpTextRecognizer(FONTS);
            boolean[] input=home("Algebra");
            for(int x=0;x<W;++x){input[83*W+x]=true;input[93*W+x]=true;}
            draw(input,1,85,6,symbol);
            List<SharpTextRecognizer.Cell> normal=special.recognize(input,W,H);
            check(has(normal,mapped,1,85),"Approved special code "+code+" in editor");
            for(int y=84;y<=92;++y) for(int x=0;x<8;++x) input[y*W+x]=!input[y*W+x];
            List<SharpTextRecognizer.Cell> inverse=special.recognizeStable(input,W,H,normal);
            check(has(inverse,mapped,1,85),"Inverse approved special code "+code);
            for(SharpTextRecognizer.Cell c:inverse) if(c.x==1&&c.y==85) check(c.inverse,"Special polarity");
        }
        check(approvedCount==45,"Exactly the 45 reviewed font symbols enabled");
        check(SharpTextRecognizer.specialCharacter(192)==0,"Unapproved accented letter not enabled");
        // Catalog functions may contain only one letter-like symbol. A
        // complete e^( is strong context even without a Home editor grid.
        int[] exp={0,0,12,18,30,16,12,0};font(1,(char)150,6,exp);
        r=new SharpTextRecognizer(FONTS);p=new boolean[W*H];
        draw(p,17,36,6,exp);draw(p,23,36,6,caret);draw(p,29,36,6,opening);
        char expCharacter=SharpTextRecognizer.specialCharacter(150);
        cs=r.recognize(p,W,H);
        check(has(cs,expCharacter,17,36)&&has(cs,'^',23,36)&&has(cs,'(',29,36),"Catalog exponential token without Home context");
        previous=cs;
        for(int y=34;y<=45;++y) for(int x=15;x<=36;++x) p[y*W+x]=!p[y*W+x];
        cs=r.recognizeStable(p,W,H,previous);
        check(has(cs,expCharacter,17,36)&&has(cs,'^',23,36)&&has(cs,'(',29,36),"Inverse Catalog exponential token");
        p=new boolean[W*H];draw(p,17,36,6,exp);draw(p,23,36,6,caret);
        check(r.recognize(p,W,H).isEmpty(),"Incomplete token remains original outside Home");
        p=new boolean[W*H];draw(p,17,36,6,exp);draw(p,24,36,6,caret);draw(p,30,36,6,opening);
        check(r.recognize(p,W,H).isEmpty(),"Separated symbols must not qualify as e^(");
        p=home("Zoom");draw(p,17,36,6,exp);draw(p,23,36,6,caret);draw(p,29,36,6,opening);
        check(!has(r.recognize(p,W,H),expCharacter,17,36),"Token-shaped pixels in graph area stay original");
        // Pretty-print integral caps are fixed while the straight stem grows.
        r=new SharpTextRecognizer(FONTS);
        for (int height : new int[]{9,14,24,40}) {
            p=home("Algebra");int[] integral=new int[height];
            integral[0]=2;integral[1]=5;integral[height-2]=20;integral[height-1]=8;
            for(int y=2;y<height-2;++y) integral[y]=4;
            draw(p,10,25,5,integral);draw(p,20,26,6,X);
            cs=r.recognize(p,W,H);
            check(has(cs,SharpTextRecognizer.specialCharacter(189),10,25),"Integral height "+height);
            boolean[] inverted=p.clone();
            for(int y=25;y<25+height;++y)for(int x=10;x<29;++x)inverted[y*W+x]=!inverted[y*W+x];
            List<SharpTextRecognizer.Cell> inv=r.recognizeStable(inverted,W,H,cs);
            check(has(inv,SharpTextRecognizer.specialCharacter(189),10,25),"Inverse integral height "+height);
            for(SharpTextRecognizer.Cell c:inv)if(c.x==10&&c.y==25)check(c.inverse,"Integral selection polarity");
            previous=cs;p[(25+height-1)*W+11]=false;
            cs=r.recognizeStable(p,W,H,previous);
            check(!has(cs,SharpTextRecognizer.specialCharacter(189),10,25),"Edited integral cap invalidates cached overlay");
        }
        p=home("Algebra");int[] graphic={2,5,4,4,4,4,4,20,8};draw(p,10,25,5,graphic);
        check(!has(r.recognize(p,W,H),SharpTextRecognizer.specialCharacter(189),10,25),"Integral-shaped graphic without expression stays original");
        p=home("Zoom");draw(p,10,25,5,graphic);draw(p,20,29,6,X);
        check(!has(r.recognize(p,W,H),SharpTextRecognizer.specialCharacter(189),10,25),"Graph integral-shaped pixels stay original");
        // A damaged F-key header cannot authorize overlays in its tile. Use a
        // false ordinary word within that tile to exercise fragment rejection.
        font(0,'F',4,new int[]{14,8,12,8,8});font(0,'1',4,new int[]{4,12,4,4,14});
        font(0,'a',4,new int[]{0,12,2,14,14});font(0,'b',4,new int[]{8,8,12,10,12});
        r=new SharpTextRecognizer(FONTS);p=new boolean[W*H];
        for(int x=0;x<W;++x)p[15*W+x]=true;
        for(int y=3;y<15;++y){p[y*W]=true;p[y*W+25]=true;p[y*W+50]=true;}
        draw(p,4,2,4,new int[]{14,8,12,8,8});draw(p,8,2,4,new int[]{4,12,4,4,14});
        draw(p,3,8,4,new int[]{0,12,2,14,14});draw(p,7,8,4,new int[]{8,8,12,10,12});
        draw(p,29,2,4,new int[]{14,8,12,8,8});draw(p,33,2,4,new int[]{4,12,4,4,14});
        draw(p,28,8,4,new int[]{0,12,2,14,14});draw(p,32,8,4,new int[]{8,8,12,10,12});
        previous=r.recognize(p,W,H);
        check(has(previous,'a',28,8),"Enabled adjacent toolbar tile recognizes normally");
        p[2*W+29]=false;cs=r.recognizeStable(p,W,H,previous);
        check(has(cs,'a',3,8),"Enabled tile remains sharp beside disabled tile");
        for(SharpTextRecognizer.Cell c:cs)check(c.x<=25||c.x>=50||c.y>=15,"Disabled tile rejects fresh and cached fragments");
        // The approved triangle replaces only an exact dropdown beside F#.
        p=new boolean[W*H];for(int x=0;x<W;++x)p[15*W+x]=true;
        for(int y=3;y<15;++y){p[y*W]=true;p[y*W+25]=true;}
        draw(p,4,2,4,new int[]{14,8,12,8,8});draw(p,8,2,4,new int[]{4,12,4,4,14});
        draw(p,12,4,3,new int[]{7,2});
        cs=r.recognize(p,W,H);
        check(has(cs,SharpTextRecognizer.TOOLBAR_DROPDOWN,12,4),"Dropdown beside intact F1");
        previous=cs;p[5*W+13]=false;
        check(!has(r.recognizeStable(p,W,H,previous),SharpTextRecognizer.TOOLBAR_DROPDOWN,12,4),"Changed arrow loses cached overlay");
        draw(p,12,4,3,new int[]{7,2});previous=r.recognize(p,W,H);
        p[2*W+4]=false;
        check(!has(r.recognizeStable(p,W,H,previous),SharpTextRecognizer.TOOLBAR_DROPDOWN,12,4),"Disabled F label rejects cached dropdown");
        draw(p,4,2,4,new int[]{14,8,12,8,8});
        previous=r.recognize(p,W,H);
        for(int y=1;y<15;++y)for(int x=1;x<25;++x)p[y*W+x]=!p[y*W+x];
        cs=r.recognizeStable(p,W,H,previous);
        check(has(cs,SharpTextRecognizer.TOOLBAR_DROPDOWN,12,4),"Inverse active toolbar dropdown");
        for(SharpTextRecognizer.Cell c:cs)if(c.glyph.character==SharpTextRecognizer.TOOLBAR_DROPDOWN)check(c.inverse,"Dropdown polarity");
        p=new boolean[W*H];draw(p,12,4,3,new int[]{7,2});
        check(!has(r.recognizeStable(p,W,H,cs),SharpTextRecognizer.TOOLBAR_DROPDOWN,12,4),"Isolated triangle remains original");
        System.out.println("Dropdown: normal/inverse toolbar context, disabled/cache rejection and isolated graphic fallback passed.");
        System.out.println("Home symbols: integral heights, cap edits, graph fallback and disabled toolbar cache/fragment rejection passed.");
        System.out.println("Catalog: normal/inverse exponential token, incomplete/separated rejection and graph fallback passed.");
        System.out.println("Special symbols: all 45 approved code mappings in normal/inverse Home input passed.");
        System.out.println("Home editor: normal/inverse punctuation, off-grid fragment rejection, cursor and clearing passed.");
        System.out.println("Pretty print: raised digits, small superscripts, nested/tall parentheses, edits, clearing and graphics fallback passed.");
    }
}
