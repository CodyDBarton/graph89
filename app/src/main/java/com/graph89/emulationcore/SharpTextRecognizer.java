package com.graph89.emulationcore;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.HashSet;

/** Exact ROM-glyph matching, independent of Android drawing and the CPU engine.
 * Each frame is recognized afresh: clearing, scrolling and state restoration
 * cannot leave a stale text overlay. Small isolated shapes are kept as pixels.
 */
public final class SharpTextRecognizer {
    public static final char TOOLBAR_DROPDOWN = '\ue200';
    private final Glyph dropdown = new Glyph(0, 3, 2, TOOLBAR_DROPDOWN, new int[]{7, 2}, true);
    public static final class Glyph {
        public final int font, width, height, ink;
        public final int minX, maxX, minY, maxY;
        public final char character;
        public final boolean mathDelimiter;
        public final int[] rows;
        Glyph(int font, int width, int height, char character, int[] rows) {
            this(font, width, height, character, rows, false);
        }
        Glyph(int font, int width, int height, char character, int[] rows, boolean mathDelimiter) {
            this.mathDelimiter = mathDelimiter;
            this.font = font; this.width = width; this.height = height;
            this.character = character; this.rows = rows;
            int count = 0, left = width, right = -1, top = height, bottom = -1;
            for (int y = 0; y < height; ++y) {
                count += Integer.bitCount(rows[y]);
                for (int x = 0; x < width; ++x) if ((rows[y] & (1 << (width - x - 1))) != 0) {
                    left = Math.min(left, x); right = Math.max(right, x);
                    top = Math.min(top, y); bottom = Math.max(bottom, y);
                }
            }
            ink = count; minX = left; maxX = right; minY = top; maxY = bottom;
        }
    }
    public static final class Cell {
        public final int x, y, clipLeft, clipTop, clipRight, clipBottom;
        public final boolean inverse;
        public final Glyph glyph;
        Cell(int x, int y, boolean inverse, Glyph glyph) {
            this(x,y,inverse,glyph,0,0,160,100);
        }
        Cell(int x,int y,boolean inverse,Glyph glyph,int left,int top,int right,int bottom) {
            this.x=x;this.y=y;this.inverse=inverse;this.glyph=glyph;
            clipLeft=left;clipTop=top;clipRight=right;clipBottom=bottom;
        }
    }
    private static final class Run {
        final List<Cell> cells = new ArrayList<Cell>();
        int letters, ink, font;
        String text() {
            StringBuilder s = new StringBuilder();
            for (Cell c : cells) s.append(c.glyph.character);
            return s.toString();
        }
    }
    private byte[] romBytes;
    private final Glyph[][] capturedGlyphs = new Glyph[3][256];
    private boolean graphFrame;
    private boolean[] disabledToolbar;
    private final Map<Character, Glyph> toolbarLabels = new HashMap<Character, Glyph>();
    private int inputBaseline = -1;
    private final Map<String, Glyph> delimiters = new HashMap<String, Glyph>();
    private final Map<Glyph, Glyph> labelIs = new HashMap<Glyph, Glyph>();
    private final List<Map<Long, List<Glyph>>> tables = new ArrayList<Map<Long, List<Glyph>>>();
    private final List<List<Integer>> widths = new ArrayList<List<Integer>>();
    /** Approved special outlines use private-use characters so the legacy
     * font's Windows encoding cannot confuse calculator symbol identities. */
    public static char specialCharacter(int romCode) {
        switch (romCode) {
            case 18:
            case 22:
            case 28:
            case 29:
            case 30:
            case 31:
            case 128:
            case 129:
            case 130:
            case 131:
            case 132:
            case 133:
            case 134:
            case 135:
            case 136:
            case 137:
            case 138:
            case 139:
            case 140:
            case 141:
            case 142:
            case 143:
            case 144:
            case 145:
            case 146:
            case 147:
            case 148:
            case 149:
            case 150:
            case 151:
            case 152:
            case 153:
            case 154:
            case 155:
            case 156:
            case 157:
            case 158:
            case 159:
            case 160:
            case 168:
            case 176:
            case 177:
            case 180:
            case 183:
            case 188:
            case 189:
            case 190:
                return (char)(0xe100 + romCode);
            default: return 0;
        }
    }
    private static boolean textAnchor(char c) {
        if (Character.isLetterOrDigit(c)) return true;
        int code = c - 0xe100;
        return c >= 0xe100 && specialCharacter(code) == c;
    }
    private static boolean homeSymbol(char c) {
        return textAnchor(c) || (c >= 0xe100 && specialCharacter(c - 0xe100) == c);
    }
    public SharpTextRecognizer(byte[] templates) {
        romBytes = templates.clone();
        if (templates.length != 3 * 256 * 12) throw new IllegalArgumentException("Font templates");
        for (int f = 0; f < 3; ++f) {
            Map<Long, List<Glyph>> table = new HashMap<Long, List<Glyph>>();
            List<Integer> fontWidths = new ArrayList<Integer>();
            for (int c = 0; c < 256; ++c) {
                char approved = c >= 33 && c < 127 ? (char)c : specialCharacter(c);
                if (approved == 0) continue;
                int offset = (f * 256 + c) * 12;
                int w = templates[offset] & 255, h = templates[offset + 1] & 255;
                if (w < 1 || w > 8 || h < 4 || h > 10) continue;
                int[] rows = new int[h];
                for (int y = 0; y < h; ++y) rows[y] = (templates[offset + 2 + y] & 255) >>> (8 - w);
                // I and | share a bitmap. Word context in the toolbar/status bands
                // decides whether to redraw I; isolated bars remain pixels.
                char character = f == 0 && (c == 'I' || c == '|') ? 0 : approved;
                Glyph glyph = new Glyph(f, w, h, character, rows);
                if (glyph.ink == 0) continue;
                capturedGlyphs[f][c] = character == approved ? glyph : new Glyph(f,w,h,approved,rows);
                if (f == 0 && (c == 'F' || (c >= '1' && c <= '8'))) toolbarLabels.put((char)c, glyph);
                long key = key(w, rows);
                List<Glyph> bucket = table.get(key);
                if (bucket == null) { bucket = new ArrayList<Glyph>(); table.put(key, bucket); }
                bucket.add(glyph);
                if (!fontWidths.contains(w)) fontWidths.add(w);
            }
            tables.add(table); widths.add(fontWidths);
        }
    }
    public Glyph compactGlyph(int f,int c,int w,int h) {
        if(c<0 || c>=256)return null;
        if(f>=0 && f<3) {
            if(capturedGlyphs[f][c]!=null)return capturedGlyphs[f][c];
            int off=(f*256+c)*12,width=romBytes[off]&255,height=romBytes[off+1]&255;
            if(width<1 || width>8 || height<1 || height>10)return null;
            int[] rows=new int[height];for(int y=0;y<height;y++)rows[y]=(romBytes[off+2+y]&255) >>> (8-width);
            return new Glyph(f,width,height,(char)0,rows);
        }
        if(f!=3 || h<7 || h>512 || (c!=189 && c!=40 && c!=41) || w!=(c==189?5:3))return null;
        String key="native:"+c+":"+h;Glyph g=delimiters.get(key);if(g!=null)return g;
        int[] rows=new int[h];java.util.Arrays.fill(rows,c==189?4:c==40?4:1);
        rows[0]=rows[h-1]=c==189?2:c==40?1:4;rows[1]=rows[h-2]=2;
        if(c==189){rows[1]=5;rows[h-2]=20;rows[h-1]=8;}
        g=new Glyph(1,w,h,c==189?specialCharacter(189):(char)c,rows,true);delimiters.put(key,g);return g;
    }
    public static final class CompactItem {
        public double x,y,scale,x1,y1;public double clipTop=16,advance=4.5,heightScale=1;public boolean inverse;public Double selectionX;public Glyph glyph;public int attribute=1;
        CompactItem(double x,double y,double scale,boolean inverse,Glyph glyph) {this.x=x;this.y=y;this.scale=scale;this.inverse=inverse;this.glyph=glyph;}
    }
    public static final class CompactScene {
        public boolean body,input,yEditor,repackedHistory;
        public double[] markerOffsets=new double[67];
        public double verticalSaved,historySaved;public int visibleHistoryEntries;
        public java.util.List<double[]> eraseRects=new ArrayList<double[]>();public java.util.List<CompactItem> items=new ArrayList<CompactItem>();
        public java.util.List<double[]> inverseRects=new ArrayList<double[]>();
        public Double cursorX;public int inputStart,inputCount,fullInputCount,extraRows;
    }
    private static void limitGap(double[] caps,int start,int a,int b,double size) {
        for(int v=Math.max(start,a);v<Math.min(start+caps.length,b);v++)caps[v-start]=Math.min(caps[v-start],size);
    }
    private double[] structureGaps(int[] p,List<Integer> members,int start,int end,boolean vertical) {
        double[] caps=new double[Math.max(0,end-start)];java.util.Arrays.fill(caps,Double.POSITIVE_INFINITY);
        List<Integer> glyphs=new ArrayList<Integer>();for(int i:members)if(p[i+2]==6)glyphs.add(i);
        for(int e:glyphs)if(p[e+7]==0) {
            int base=-1;
            for(int b:glyphs)if(p[b+7]==1 && p[b+1]>p[e+1] && p[e+1]+p[e+6]<=p[b+1]+3 && p[e]>=p[b]+p[b+5] && p[e]-p[b]-p[b+5]<=8)
                if(base<0 || p[b]+p[b+5]>p[base]+p[base+5])base=b;
            if(base>=0){if(vertical)limitGap(caps,start,p[e+1]+p[e+6],p[base+1],0.5);else limitGap(caps,start,p[base]+p[base+5],p[e],0.75);}
        }
        for(int line:members)if(p[line+2]==7 && p[line+1]==p[line+4] && Math.abs(p[line]-p[line+3])>=5) {
            int l=Math.min(p[line],p[line+3]),r=Math.max(p[line],p[line+3])+1,y=p[line+1];
            int above=Integer.MIN_VALUE,below=Integer.MAX_VALUE,left=Integer.MAX_VALUE,right=Integer.MIN_VALUE;
            for(int g:glyphs)if(p[g]>=l && p[g]+p[g+5]<=r && p[g+7]!=3) {
                left=Math.min(left,p[g]);right=Math.max(right,p[g]+p[g+5]);
                if(p[g+1]+p[g+6]<=y)above=Math.max(above,p[g+1]+p[g+6]);
                if(p[g+1]>y)below=Math.min(below,p[g+1]);
            }
            if(above==Integer.MIN_VALUE || below==Integer.MAX_VALUE)continue;
            if(vertical){limitGap(caps,start,above,y,0.75);limitGap(caps,start,y+1,below,0.75);}
            else {limitGap(caps,start,l+1,left,0.75);limitGap(caps,start,right,r-1,0.75);}
        }
        for(int integral:glyphs)if(p[integral+3]==189) {
            int body=-1;
            for(int b:glyphs)if(p[b+7]==1 && p[b]>=p[integral]+p[integral+5] && p[b]-p[integral]-p[integral+5]<=12 && p[b+1]>=p[integral+1] && p[b+1]<p[integral+1]+p[integral+6])
                if(body<0 || p[b]<p[body])body=b;
            if(body<0)continue;
            if(!vertical)limitGap(caps,start,p[integral]+p[integral+5],p[body],1);
            else for(int bound:glyphs)if(p[bound+7]==0 && p[bound]>=p[integral]-4 && p[bound]<=p[integral]+p[integral+5]+12) {
                if(p[bound+1]+p[bound+6]<=p[body+1])limitGap(caps,start,p[bound+1]+p[bound+6],p[body+1],1);
                if(p[bound+1]>=p[body+1]+p[body+6])limitGap(caps,start,p[body+1]+p[body+6],p[bound+1],1);
            }
        }
        return caps;
    }
    private double[] mathSpacing(int[] p,List<Integer> members,int left,int right) {
        int width=right-left;if(width<=0 || width>4096)return new double[0];
        boolean[] occupied=new boolean[width];
        for(int i:members) {
            int x=p[i],kind=p[i+2],begin=kind==6?x:Math.min(x,p[i+3]),end=kind==6?x+p[i+5]:Math.max(x,p[i+3])+1;
            for(int column=Math.max(left,begin);column<Math.min(right,end);column++)
                if(kind==6 || p[i+1]!=p[i+4] || column==begin || column==end-1)occupied[column-left]=true;
        }
        double[] caps=structureGaps(p,members,left,right,false);
        double[] map=new double[width+1];int column=0;double position=left;map[0]=position;
        while(column<width) {
            int end=column+1;if(!occupied[column])while(end<width && !occupied[end])end++;
            int length=end-column;double cap=Double.POSITIVE_INFINITY;for(int v=column;v<end;v++)cap=Math.min(cap,caps[v]);double step=occupied[column]?1:Math.max(0.5,Math.min(Math.max(1,length*0.5),cap))/length;
            while(column<end){position+=step;map[++column]=position;}
        }
        return map;
    }
    private double[] verticalSpacing(int[] p,List<Integer> members,int top,int bottom) {
        int height=bottom-top;if(height<=0 || height>4096)return new double[0];
        List<Integer> shapes=new ArrayList<Integer>();
        for(int i:members)if(p[i+2]==6 && p[i+7]==3 && (p[i+3]==40 || p[i+3]==41 || p[i+3]==189))shapes.add(i);
        boolean[] occupied=new boolean[height];
        for(int i:members) {
            int kind=p[i+2],y=p[i+1],begin=kind==6?y:Math.min(y,p[i+4]),end=kind==6?y+p[i+6]:Math.max(y,p[i+4])+1;
            boolean duplicate=false;
            if(kind==7)for(int j:shapes)if(Math.min(p[i],p[i+3])>=p[j] && Math.max(p[i],p[i+3])<p[j]+p[j+5] && begin>=p[j+1] && end<=p[j+1]+p[j+6]){duplicate=true;break;}
            if(duplicate)continue;
            boolean elastic=shapes.contains(i);
            for(int row=Math.max(top,begin);row<Math.min(bottom,end);row++)if(!elastic || row<begin+2 || row>=end-2)occupied[row-top]=true;
        }
        double[] caps=structureGaps(p,members,top,bottom,true);
        double[] map=new double[height+1];int row=0;double position=top;map[0]=position;
        while(row<height){int end=row+1;if(!occupied[row])while(end<height && !occupied[end])end++;
            int length=end-row;double cap=Double.POSITIVE_INFINITY;for(int v=row;v<end;v++)cap=Math.min(cap,caps[v]);double step=occupied[row]?1:Math.max(0.5,Math.min(Math.max(0.5,length*0.5),cap))/length;
            while(row<end){position+=step;map[++row]=position;}}
        return map;
    }
    private static double packed(double x,double left,double[] map) {
        int index=(int)x-(int)left;return index>=0 && index<map.length?map[index]:x;
    }
    private static final class HistoryGroup {
        int group,entry;double top,bottom;
        HistoryGroup(int group,int entry,double top,double bottom){this.group=group;this.entry=entry;this.top=top;this.bottom=bottom;}
    }
    private static final class HistoryBand {
        double top,bottom;List<HistoryGroup> groups=new ArrayList<HistoryGroup>();
        HistoryBand(HistoryGroup g){top=g.top;bottom=g.bottom;groups.add(g);}
    }
    private Map<Integer,Double> historyOffsets(int[] p,CompactScene scene) {
        Map<Integer,Double> offsets=new HashMap<Integer,Double>();boolean complete=false;
        for(int i=0;i+11<p.length;i+=12)if(p[i+2]==13)complete=true;
        if(scene.yEditor || !complete)return offsets;
        List<HistoryGroup> groups=new ArrayList<HistoryGroup>();
        for(int h=0;h+11<p.length;h+=12)if(p[h+2]==5) {
            if(p[h+6]<=0 || (p[h+7]!=1 && p[h+7]!=2))return offsets;
            List<Integer> members=new ArrayList<Integer>();int top=Integer.MAX_VALUE,bottom=Integer.MIN_VALUE;
            for(int i=0;i+11<p.length;i+=12)if((p[i+2]==6 || p[i+2]==7) && p[i+8]==p[h+3]) {
                members.add(i);top=Math.min(top,p[i+2]==7?Math.min(p[i+1],p[i+4]):p[i+1]);
                bottom=Math.max(bottom,p[i+2]==7?Math.max(p[i+1],p[i+4])+1:p[i+1]+p[i+6]);
            }
            if(members.isEmpty() || members.size()!=p[h+5])return offsets;
            if(top>=83)continue; // Newer entries below the native viewport stay below it.
            double[] map=verticalSpacing(p,members,top,bottom);
            double height=(map.length>0?map[map.length-1]-top:bottom-top)*0.72,y=83+(bottom-83)*0.72;
            groups.add(new HistoryGroup(p[h+3],p[h+6],y-height,y));
        }
        if(groups.isEmpty())return offsets;
        Collections.sort(groups,new Comparator<HistoryGroup>(){public int compare(HistoryGroup a,HistoryGroup b){int c=Double.compare(a.top,b.top);return c!=0?c:Integer.compare(a.group,b.group);}});
        List<HistoryBand> bands=new ArrayList<HistoryBand>();
        for(HistoryGroup g:groups) {
            HistoryBand last=bands.isEmpty()?null:bands.get(bands.size()-1);
            if(last!=null && g.top<last.bottom-0.001){last.bottom=Math.max(last.bottom,g.bottom);last.groups.add(g);}
            else bands.add(new HistoryBand(g));
        }
        double target=Math.min(82.28,bands.get(bands.size()-1).bottom),end=target;Set<Integer> visible=new HashSet<Integer>();
        for(int i=bands.size()-1;i>=0;i--) {
            HistoryBand b=bands.get(i);double shift=target-b.bottom;
            for(HistoryGroup g:b.groups){offsets.put(g.group,shift);if(g.bottom+shift>16 && g.top+shift<83)visible.add(g.entry);}
            boolean samePair=false;
            if(i>0)for(HistoryGroup a:bands.get(i-1).groups)for(HistoryGroup g:b.groups)if(a.entry==g.entry)samePair=true;
            target=b.top+shift-(samePair?1:2);
        }
        scene.repackedHistory=true;scene.visibleHistoryEntries=visible.size();
        scene.historySaved=Math.max(0,bands.get(bands.size()-1).bottom-bands.get(0).top-(end-(target+2)));
        return offsets;
    }
    private static double inputAdvance(int code) {
        if(code==32)return 3.2;
        switch(code){case 33:case 39:case 44:case 46:case 58:case 59:case 73:case 105:case 108:case 124:return 3.6;case 40:case 41:return 3.9;default:return 4.5;}
    }
    private int compactStart,compactEditor=-1;
    public CompactScene compactScene(int[] packets) {
        CompactScene scene=new CompactScene();if(packets==null)return scene;
        for(int i=0;i+11<packets.length;i+=12)if(packets[i+2]==10)scene.yEditor=true;
        for(int i=0;i+11<packets.length;i+=12)if(packets[i+2]==11 && packets[i]==7 && packets[i+3]==121)scene.extraRows++;
        scene.body=scene.yEditor;Map<Integer,Double> offsets=historyOffsets(packets,scene);double base=scene.yEditor?16:83;
        for(int h=0;h+11<packets.length;h+=12)if(packets[h+2]==5) {
            List<Integer> members=new ArrayList<Integer>();double left=Double.MAX_VALUE,right=-Double.MAX_VALUE;
            for(int i=0;i+11<packets.length;i+=12)if((packets[i+2]==6 || packets[i+2]==7) && packets[i+8]==packets[h+3]) {
                members.add(i);left=Math.min(left,packets[i]);right=Math.max(right,packets[i+2]==7?Math.max(packets[i],packets[i+3])+1:packets[i]+packets[i+5]);
            }
            if(members.isEmpty() || members.size()!=packets[h+5])continue;
            boolean output=!scene.yEditor && (packets[h+7]==1 || (packets[h+7]==0 && right>=158 && right<=162));
            double anchor=scene.yEditor?0:8,scale=0.72;boolean inverse=packets[h+4]!=0;
            double[] map=mathSpacing(packets,members,(int)left,(int)right);
            boolean fitsOutput=output && (packed(right,left,map)-packed(left,left,map))*scale<=152;
            // One translation applies equally to glyphs, rules and selection.
            double shift=fitsOutput?160-(packed(right,left,map)-anchor)*scale-anchor:0;
            double top=Double.MAX_VALUE,bottom=-Double.MAX_VALUE;
            for(int i:members){top=Math.min(top,packets[i+2]==7?Math.min(packets[i+1],packets[i+4]):packets[i+1]);bottom=Math.max(bottom,packets[i+2]==7?Math.max(packets[i+1],packets[i+4])+1:packets[i+1]+packets[i+6]);}
            double[] vertical=verticalSpacing(packets,members,(int)top,(int)bottom);
            double yAnchor=scene.yEditor?top:bottom;
            if(scene.yEditor)for(int i=0;i+11<packets.length;i+=12)if((packets[i+2]==1 || packets[i+2]==11) && packets[i]>=19 && packets[i]<=31 && packets[i]<left && packets[i+3]==61 && packets[i+1]>=top && packets[i+1]<bottom){yAnchor=packets[i+1];break;}
            double yShift=yAnchor-packed(yAnchor,top,vertical);double historyShift=offsets.containsKey(packets[h+3])?offsets.get(packets[h+3]):0;
            scene.verticalSaved+=(bottom-top-(packed(bottom,top,vertical)-packed(top,top,vertical)))*scale;
            if(!scene.yEditor && !output && left<40)for(int row=Math.max(16,(int)top);row<Math.min(83,(int)bottom);row++)scene.markerOffsets[row-16]=(packed(row,top,vertical)+yShift-row)*scale;

            scene.body=true;
            if(scene.repackedHistory && packets[h+7]==2)for(int i=0;i+11<packets.length;i+=12)
                if(packets[i+2]==12 && packets[i+8]==packets[h+6]) {
                    Glyph g=compactGlyph(packets[i+7],packets[i+3],0,0);
                    if(g!=null)scene.items.add(new CompactItem(packets[i]*scale,base+(packed(packets[i+1],top,vertical)+yShift-base)*scale+historyShift,scale,false,g));
                }
            if(inverse) {
                scene.inverseRects.add(new double[]{anchor+(packed(left,left,map)-anchor)*scale+shift-0.5,base+(packed(top,top,vertical)+yShift-base)*scale+historyShift,(packed(right,left,map)-packed(left,left,map))*scale+0.5,(packed(bottom,top,vertical)-packed(top,top,vertical))*scale});
            }
            if(scene.yEditor) {
                scene.eraseRects.add(new double[]{left,top,right-left,bottom-top,inverse?1:0});
            }
            for(int i:members) {
                boolean stem=false;
                if(packets[i+2]==7 && packets[i]==packets[i+3])for(int j:members)
                    if(packets[j+2]==6 && packets[j+7]==3 && packets[i]>=packets[j] && packets[i]<packets[j]+packets[j+5]
                        && Math.min(packets[i+1],packets[i+4])>=packets[j+1] && Math.max(packets[i+1],packets[i+4])<packets[j+1]+packets[j+6]) {stem=true;break;}
                if(stem)continue;
                double x=anchor+(packed(packets[i],left,map)-anchor)*scale+shift,y=base+(packed(packets[i+1],top,vertical)+yShift-base)*scale+historyShift;
                if(packets[i+2]==6) {
                    Glyph g=compactGlyph(packets[i+7],packets[i+3],packets[i+5],packets[i+6]);if(g==null)continue;
                    CompactItem item=new CompactItem(x,y,scale,inverse,g);if(packets[i+7]==3)item.heightScale=(packed(packets[i+1]+packets[i+6],top,vertical)-packed(packets[i+1],top,vertical))/packets[i+6];if(scene.yEditor)item.clipTop=21.04;scene.items.add(item);
                }else {
                    CompactItem item=new CompactItem(x,y,scale,inverse,null);
                    item.x1=anchor+(packed(packets[i+3],left,map)-anchor)*scale+shift;item.y1=base+(packed(packets[i+4],top,vertical)+yShift-base)*scale+historyShift;item.attribute=packets[i+5];if(scene.yEditor)item.clipTop=21.04;scene.items.add(item);
                }
            }
        }
        if(scene.yEditor) {
            for(int i=0;i+11<packets.length;i+=12)if(((packets[i+2]>=0 && packets[i+2]<=3 && packets[i+1]<83) || (packets[i+2]==11 && packets[i+1]<110)) && packets[i+1]>=16) {
                double x=packets[i],y=packets[i+1];boolean grouped=false;
                for(double[] r:scene.eraseRects)if(x>=r[0] && x<r[0]+r[2] && y>=r[1] && y<r[1]+r[3]){grouped=true;break;}
                if(grouped)continue;
                Glyph g=compactGlyph(packets[i+2]==11?packets[i+7]:packets[i+2],packets[i+3],packets[i+5],packets[i+6]);if(g==null)continue;
                CompactItem item=new CompactItem(x*0.72,16+(y-16)*0.72,0.72,packets[i+4]!=0,g);
                item.clipTop=16+(Math.max(16,packets[i+9])-16)*0.72;scene.items.add(item);
            }
            for(int i=0;i+11<packets.length;i+=12)if(((packets[i+2]>=0 && packets[i+2]<=3 && packets[i+1]<83) || (packets[i+2]==11 && packets[i+1]<110)) && packets[i+1]>=16) {
                Glyph g=compactGlyph(packets[i+2]==11?packets[i+7]:packets[i+2],packets[i+3],packets[i+5],packets[i+6]);if(g==null || g.maxX<g.minX)continue;
                scene.eraseRects.add(new double[]{packets[i]+g.minX,packets[i+1]+g.minY,g.maxX-g.minX+1,g.maxY-g.minY+1,packets[i+4]});
            }
        }
        for(int h=0;h+11<packets.length;h+=12)if(packets[h+2]==8) {
            int n=packets[h+5],cur=packets[h],flags=packets[h+3],selection=packets[h+4],count=0;
            for(int i=0;i+11<packets.length;i+=12)if(packets[i+2]==9)count++;
            if(n<0 || n>512 || cur<0 || cur>n || count!=n)break;
            boolean yInput=packets[h+6]==1;double left=yInput?packets[h+8]*0.75:1;
            double[] advances=new double[n],positions=new double[n+1];java.util.Arrays.fill(advances,4.5);
            for(int i=0;i+11<packets.length;i+=12)if(packets[i+2]==9){int index=packets[i];if(index<0 || index>=n)return scene;advances[index]=inputAdvance(packets[i+3]);}
            for(int index=0;index<n;index++)positions[index+1]=positions[index]+advances[index];
            double available=159-left;int id=packets[h+7];
            if(compactEditor!=id){compactEditor=id;compactStart=0;}
            compactStart=Math.min(compactStart,n);
            if(cur<compactStart)compactStart=cur;
            while(compactStart<cur && positions[cur]-positions[compactStart]>available)compactStart++;
            while(compactStart>0 && positions[n]-positions[compactStart-1]<=available)compactStart--;
            int start=compactStart,end=start;
            while(end<n && positions[end]-positions[start]+Math.max(advances[end],4.5)<=available)end++;
            if(yInput)for(int i=0;i+11<packets.length;i+=12)if(packets[i+2]==1 && packets[i+1]==85 && packets[i]<packets[h+8]) {
                Glyph g=compactGlyph(1,packets[i+3],0,0);if(g!=null)scene.items.add(new CompactItem(0.5+packets[i]*0.75,85.8,0.8,packets[i+4]!=0,g));
            }
            scene.input=true;scene.inputStart=start;scene.inputCount=end-start;scene.fullInputCount=n;
            for(int i=0;i+11<packets.length;i+=12)if(packets[i+2]==9) {
                int index=packets[i];if(index<start || index>=end)continue;
                Glyph g=compactGlyph(1,packets[i+3],0,0);if(g==null)continue;
                boolean inverse=(flags&32)!=0 && (flags&512)!=0 && index>=Math.min(selection,cur) && index<Math.max(selection,cur);
                CompactItem item=new CompactItem(left+positions[index]-positions[start]+(advances[index]-g.width*0.8)/2,85.8,0.8,inverse,g);item.advance=advances[index];item.selectionX=left+positions[index]-positions[start];scene.items.add(item);
            }
            scene.cursorX=left+positions[cur]-positions[start];
            break;
        }
        if(!scene.input){compactEditor=-1;compactStart=0;}
        return scene;
    }
    /** Remove only a cursor positively identified by the native drawing call. */
    public static int[] cursor(int[] packets) {
        if(packets!=null)for(int i=0;i+11<packets.length;i+=12)
            if(packets[i+2]==4 && packets[i]>=0 && packets[i]+2<=160 && packets[i]%6==0
                && packets[i+1]==85 && packets[i+5]==2 && packets[i+6]==8
                && packets[i+4]>0 && packets[i+4]<=255)
                return new int[]{packets[i],packets[i+4]};
        return null;
    }
    public static boolean[] withoutCursor(boolean[] pixels,int[] packets) {
        int[] cursor=cursor(packets);if(cursor==null || pixels.length!=16000)return pixels;
        boolean[] clean=pixels.clone();
        for(int y=0;y<8;y++)if((cursor[1]&(1<<y))!=0)for(int x=0;x<2;x++) {
            int i=(85+y)*160+cursor[0]+x;clean[i]=!clean[i];
        }
        return clean;
    }
    /** Merge ROM-supplied identities over pixel-recognized fallback cells. */
    private boolean[] framePixels;
    private boolean homeFrame;
    public List<Cell> retained(int[] packets, List<Cell> fallback) {
        List<Cell> direct = new ArrayList<Cell>();
        if (packets != null) for(int i=0;i+11<packets.length;i+=12) {
            int x=packets[i],y=packets[i+1],f=packets[i+2],c=packets[i+3];
            if(f<0 || f>3 || c<0 || c>=256 || packets[i+7]==3)continue;
            Glyph g=null;
            if(f<3)g=capturedGlyphs[f][c];
            else {
                int h=packets[i+6],w=c==189?5:3;
                if(h<7 || h>512 || (c!=189 && c!=40 && c!=41) || packets[i+5]!=w)continue;
                int[] rows=new int[h];java.util.Arrays.fill(rows,c==189?4:c==40?4:1);
                rows[0]=rows[h-1]=c==189?2:c==40?1:4;rows[1]=rows[h-2]=2;
                if(c==189){rows[1]=5;rows[h-2]=20;rows[h-1]=8;}
                String key="native:"+c+":"+h;g=delimiters.get(key);
                if(g==null){g=new Glyph(1,w,h,c==189?specialCharacter(189):(char)c,rows,true);delimiters.put(key,g);}
            }
            int l=packets[i+8],t=packets[i+9],r=packets[i+10],b=packets[i+11];
            if(g==null || g.width!=packets[i+5] || g.height!=packets[i+6]
                || l<0 || t<0 || r>160 || b>100 || l>=r || t>=b
                || x+g.width<=l || x>=r || y+g.height<=t || y>=b)continue;
            direct.add(new Cell(x,y,packets[i+4]!=0,g,l,t,r,b));
        }
        List<Cell> result=new ArrayList<Cell>(direct);
        for(Cell c:fallback) {
            boolean covered=false;
            for(Cell d:direct) if(c.x<Math.min(d.clipRight,d.x+d.glyph.width) && Math.max(d.clipLeft,d.x)<c.x+c.glyph.width
                && c.y<Math.min(d.clipBottom,d.y+d.glyph.height) && Math.max(d.clipTop,d.y)<c.y+c.glyph.height){covered=true;break;}
            if(!covered)result.add(c);
        }
        if (framePixels != null && homeFrame && !graphFrame) {
            boolean[] occupied=disabledToolbar.clone();
            if(inputBaseline>=0)for(int y=inputBaseline;y<inputBaseline+8;y++)
                for(int x=0;x<160;x++)occupied[y*160+x]=true;
            for(Cell c:direct)occupy(c,occupied,160);
            List<Cell> shaped=new ArrayList<Cell>(result);
            addMathIntegrals(framePixels,160,100,occupied,result,shaped,true);
            addMathDelimiters(framePixels,160,100,occupied,shaped);
            List<Cell> shapes=new ArrayList<Cell>(shaped.subList(result.size(),shaped.size()));
            List<Cell> merged=new ArrayList<Cell>();
            for(Cell c:result) {
                boolean covered=false;
                for(Cell d:shapes)if(c.x<d.x+d.glyph.width && d.x<c.x+c.glyph.width
                    && c.y<d.y+d.glyph.height && d.y<c.y+c.glyph.height){covered=true;break;}
                if(!covered)merged.add(c);
            }
            merged.addAll(shapes);return merged;
        }
        return result;
    }
    private static long key(int width, int[] rows) {
        long key = width;
        for (int y = 0; y < 4; ++y) key = (key << 8) | rows[y];
        return key;
    }
    private static int row(boolean[] pixels, int screenWidth, int x, int y, int width, boolean inverse) {
        int value = 0;
        for (int i = 0; i < width; ++i) {
            boolean ink = x + i < screenWidth && pixels[y * screenWidth + x + i] != inverse;
            value = (value << 1) | (ink ? 1 : 0);
        }
        return value;
    }
    private Cell match(boolean[] pixels, int screenWidth, int screenHeight, int f, int x, int y) {
        Cell best = null;
        for (int w : widths.get(f)) {
            // A clipped trailing blank column is safe, but clipped ink never matches.
            if (x + w > screenWidth + 1) continue;
            for (int polarity = 0; polarity < 2; ++polarity) {
                boolean inverse = polarity != 0;
                int height = f == 0 ? 5 : (f == 1 ? 8 : 10);
                boolean trailingCursor = x + w < screenWidth && y + height <= screenHeight;
                if (trailingCursor) for (int j = 0; j < height; ++j)
                    if (pixels[(y + j) * screenWidth + x + w - 1] == inverse
                        || pixels[(y + j) * screenWidth + x + w] == inverse) { trailingCursor = false; break; }
                // The ROM draws a two-column cursor across the final padding
                // column and the next cell. Recognize again after a transient
                // cursor update; do not wait for an entire cursor-off phase.
                for (int masked = 0; masked <= (trailingCursor ? 1 : 0); ++masked) {
                    int mask = masked == 1 ? ~1 : -1;
                    long key = w;
                    for (int j = 0; j < 4; ++j)
                        key = (key << 8) | (row(pixels, screenWidth, x, y + j, w, inverse) & mask);
                    List<Glyph> candidates = tables.get(f).get(key);
                    if (candidates == null) continue;
                    for (Glyph g : candidates) {
                        if (y + g.height > screenHeight) continue;
                        boolean same = true;
                        for (int j = 0; j < g.height; ++j) {
                            if ((masked == 1 && (g.rows[j] & 1) != 0)
                                || (row(pixels, screenWidth, x, y + j, w, inverse) & mask) != g.rows[j]) { same = false; break; }
                        }
                        if (same && (best == null || w > best.glyph.width || (w == best.glyph.width && g.ink > best.glyph.ink)))
                            best = new Cell(x, y, inverse, g);
                    }
                }
            }
        }
        return best;
    }
    private static boolean blank(boolean[] pixels, int sw, int x0, int x1, int y, int height, boolean inverse) {
        if (x0 < 0 || x1 > sw) return false;
        for (int j = y; j < y + height; ++j)
            for (int x = x0; x < x1; ++x)
                if (pixels[j * sw + x] != inverse) return false;
        return true;
    }
    private static boolean overlaps(Cell c, boolean[] occupied, int sw) {
        for (int y = Math.max(c.y,c.clipTop); y < Math.min(c.clipBottom,c.y + c.glyph.height); ++y)
            for (int x = Math.max(c.x,c.clipLeft); x < Math.min(c.clipRight, c.x + c.glyph.width); ++x)
                if (occupied[y * sw + x]) return true;
        return false;
    }
    private static void occupy(Cell c, boolean[] occupied, int sw) {
        for (int y = Math.max(c.y,c.clipTop); y < Math.min(c.clipBottom,c.y + c.glyph.height); ++y)
            for (int x = Math.max(c.x,c.clipLeft); x < Math.min(c.clipRight, c.x + c.glyph.width); ++x) occupied[y * sw + x] = true;
    }
    private static boolean smallIWordContext(Run run, int index, boolean[] pixels, int sw, int sh) {
        Cell c = run.cells.get(index);
        if (!(c.y < 14 || c.y >= sh - 12)) return false;
        // Menu-box dividers can touch a word and have the same five-pixel
        // segment as I. A line continuing beyond the text is still a divider.
        int stem = c.x + c.glyph.minX, bottom = c.y + c.glyph.height;
        if (c.y >= 2 && pixels[(c.y - 1) * sw + stem] != c.inverse
            && pixels[(c.y - 2) * sw + stem] != c.inverse) return false;
        if (bottom + 1 < sh && pixels[bottom * sw + stem] != c.inverse
            && pixels[(bottom + 1) * sw + stem] != c.inverse) return false;
        if (index > 0) {
            Cell before = run.cells.get(index - 1);
            if (Character.isLetter(before.glyph.character) && before.x + before.glyph.width == c.x) return true;
        }
        if (index + 1 < run.cells.size()) {
            Cell after = run.cells.get(index + 1);
            if (Character.isLetter(after.glyph.character) && c.x + c.glyph.width == after.x) return true;
        }
        return false;
    }
    private Cell labelI(Cell cell) {
        Glyph original = cell.glyph;
        Glyph letter = labelIs.get(original);
        if (letter == null) {
            letter = new Glyph(original.font, original.width, original.height, 'I', original.rows);
            labelIs.put(original, letter);
        }
        return new Cell(cell.x, cell.y, cell.inverse, letter);
    }
    private static boolean confirmedSmallI(List<Cell> fresh, Cell previous) {
        for (Cell c : fresh) if (c.x == previous.x && c.y == previous.y
            && c.glyph.font == 0 && c.glyph.character == 'I') return true;
        return false;
    }
    /** Keep previously recognized cells only while their actual glyph pixels
     * still match. Cursor/selection changes in blank cell padding cannot turn
     * unchanged letters back into bitmap text. No time-based stale-text hold. */
    public List<Cell> recognizeStable(boolean[] pixels, int sw, int sh, List<Cell> previous) {
        List<Cell> fresh = recognize(pixels, sw, sh);
        List<Cell> result = new ArrayList<Cell>();
        boolean[] occupied = new boolean[pixels.length];
        for (Cell cell : previous) {
            // The Home editor has a fixed font/grid. Reacquire it from that
            // grid each frame instead of preserving an off-grid fragment.
            if (inputBaseline >= 0 && cell.y < inputBaseline + 8
                && cell.y + cell.glyph.height > inputBaseline) continue;
            if (cell.glyph.font == 0 && cell.glyph.character == 'I' && !confirmedSmallI(fresh, cell)) continue;
            if (cell.glyph.mathDelimiter && !confirmedDelimiter(fresh, cell)) continue;
            if (cell.x < 0 || cell.y < 0 || cell.y + cell.glyph.height > sh || cell.x >= sw
                || overlaps(cell, occupied, sw) || overlaps(cell, disabledToolbar, sw) || (graphFrame && cell.y >= 14 && cell.y < sh - 12)) continue;
            for (int polarity = 0; polarity < 2; ++polarity) {
                boolean inverse = polarity != 0, matches = true;
                if (cell.glyph.font == 0 && inverse && cell.y >= 14 && cell.y < sh - 12
                    && !clearInkBorder(new Cell(cell.x, cell.y, inverse, cell.glyph), pixels, sw, sh)) continue;
                Glyph g = cell.glyph;
                for (int y = g.minY; y <= g.maxY && matches; ++y)
                    for (int x = g.minX; x <= g.maxX; ++x) {
                        if (cell.x + x >= sw) { matches = false; break; }
                        boolean expected = ((g.rows[y] >> (g.width - x - 1)) & 1) != 0;
                        if ((pixels[(cell.y + y) * sw + cell.x + x] != inverse) != expected) {
                            matches = false; break;
                        }
                    }
                // Only a solid cursor column (or bottom underline) may differ
                // in padding. Arbitrary new pixels must invalidate the old cell.
                for (int y = 0; y < g.height && matches; ++y)
                    for (int x = 0; x < g.width && cell.x + x < sw; ++x) {
                        if (x >= g.minX && x <= g.maxX && y >= g.minY && y <= g.maxY) continue;
                        if (pixels[(cell.y + y) * sw + cell.x + x] == inverse) continue;
                        boolean cursor = x < g.minX || x > g.maxX;
                        if (cursor) for (int j = 0; j < g.height; ++j)
                            if (pixels[(cell.y + j) * sw + cell.x + x] == inverse) { cursor = false; break; }
                        if (!cursor && y == g.height - 1 && y > g.maxY) {
                            cursor = true;
                            for (int j = 0; j < g.width && cell.x + j < sw; ++j)
                                if (pixels[(cell.y + y) * sw + cell.x + j] == inverse) { cursor = false; break; }
                        }
                        if (!cursor) { matches = false; break; }
                    }
                if (matches) {
                    Cell kept = new Cell(cell.x, cell.y, inverse, g);
                    occupy(kept, occupied, sw); result.add(kept); break;
                }
            }
        }
        for (Cell cell : fresh) if (!overlaps(cell, occupied, sw)) {
            occupy(cell, occupied, sw); result.add(cell);
        }
        return result;
    }
    public List<Cell> recognize(boolean[] pixels, int sw, int sh) {
        if (pixels.length != sw * sh) throw new IllegalArgumentException("LCD dimensions");
        List<Run> runs = new ArrayList<Run>();
        List<Cell> singles = new ArrayList<Cell>();
        boolean home = false, graph = false, tools = false, prgm = false;
        disabledToolbar = disabledToolbar(pixels, sw, sh);
        for (int f = 2; f >= 0; --f) {
            int height = f == 0 ? 5 : (f == 1 ? 8 : 10);
            int maxGap = f == 0 ? 2 : (f == 1 ? 6 : 8);
            for (int y = 0; y <= sh - height; ++y) {
                Cell[] line = new Cell[sw];
                for (int x = 0; x < sw; ++x) {
                    line[x] = match(pixels, sw, sh, f, x, y);
                    if (line[x] != null && overlaps(line[x], disabledToolbar, sw)) line[x] = null;
                    // A small inverse glyph can coincidentally match holes in
                    // a larger normal symbol (notably e^( beside its cursor).
                    // Real inverse body text has an inverse background border.
                    if (line[x] != null && f == 0 && line[x].inverse
                        && y >= 14 && y < sh - 12 && !clearInkBorder(line[x], pixels, sw, sh)) line[x] = null;
                    if (line[x] != null && homeSymbol(line[x].glyph.character)) singles.add(line[x]);
                }
                for (int start = 0; start < sw; ++start) {
                    if (line[start] == null || !textAnchor(line[start].glyph.character)) continue;
                    Run run = new Run(); run.font = f;
                    Cell cell = line[start];
                    while (cell != null) {
                        run.cells.add(cell); run.ink += cell.glyph.ink;
                        if (textAnchor(cell.glyph.character)) ++run.letters;
                        int end = cell.x + cell.glyph.width;
                        Cell next = null;
                        for (int x = end; x < sw && x <= end + maxGap; ++x) {
                            if (line[x] != null && line[x].inverse == cell.inverse) { next = line[x]; break; }
                            if (!blank(pixels, sw, x, x + 1, y, height, cell.inverse)) break;
                        }
                        cell = next;
                    }
                    if ((run.letters >= 2 || exponentialToken(run)) && run.ink >= 8) {
                        runs.add(run);
                        if (y < 14) {
                            String text = run.text();
                            home |= text.contains("Algebra");
                            tools |= text.contains("Tools"); prgm |= text.contains("Prgm");
                            graph |= text.contains("Zoom") || text.contains("Trace") || text.contains("ReGraph");
                        }
                    }
                }
            }
        }
        home |= tools && prgm && homeInputBorders(pixels, sw, sh);
        graphFrame = graph;
        homeFrame=home;framePixels=sw==160 && sh==100 ? pixels:null;
        Collections.sort(runs, new Comparator<Run>() {
            public int compare(Run a, Run b) {
                if (a.font != b.font) return b.font - a.font;
                return b.ink - a.ink;
            }
        });
        boolean[] occupied = disabledToolbar.clone();
        List<Cell> result = new ArrayList<Cell>();
        inputBaseline = home && !graph && homeInputBorders(pixels, sw, sh) ? sh - 15 : -1;
        if (inputBaseline >= 0) {
            // Unlike pretty print, the input editor is one eight-row medium
            // font line on a six-column grid. Recognize punctuation directly,
            // even beside unsupported characters or without a two-letter run.
            for (int x = 1; x < sw; x += 6) {
                Cell c = match(pixels, sw, sh, 1, x, inputBaseline);
                if (c != null && c.glyph.width == 6 && c.glyph.character != 0) result.add(c);
            }
            // Reserve the whole line, including unmatched symbols: small-font
            // matches inside its normal/inverse shapes are never editor text.
            for (int y = inputBaseline; y < inputBaseline + 8; ++y)
                for (int x = 0; x < sw; ++x) occupied[y * sw + x] = true;
        }
        if (home && !graph) addMathIntegrals(pixels, sw, sh, occupied, singles, result,false);
        for (Run run : runs) {
            boolean overlap = false;
            for (Cell c : run.cells) if (overlaps(c, occupied, sw)) { overlap = true; break; }
            if (overlap) continue;
            for (int index = 0; index < run.cells.size(); ++index) {
                Cell c = run.cells.get(index);
                occupy(c, occupied, sw);
                if (c.glyph.font == 0 && c.glyph.character == 0) {
                    if (smallIWordContext(run, index, pixels, sw, sh)) result.add(labelI(c));
                    continue;
                }
                if (c.glyph.character != 0 && !(graph && c.y >= 14 && c.y < sh - 12)) result.add(c);
            }
        }
        // Pretty print mixes font sizes and baselines. Check the actual ink
        // border, not the cell's outer padding: a neighbouring tall delimiter
        // may touch padding without touching the exponent's ink.
        if (home && !graph) for (Cell c : singles) {
            if (c.inverse || c.y < 14 || c.y + c.glyph.height > sh - 12
                || overlaps(c, occupied, sw) || !clearInkBorder(c, pixels, sw, sh)) continue;
            occupy(c, occupied, sw); result.add(c);
        }
        if (home && !graph) addMathDelimiters(pixels, sw, sh, occupied, result);
        addToolbarDropdowns(pixels, sw, sh, occupied, result);
        return result;
    }

    /** A disabled F-key loses pixels from both its label and title. Reserve
     * the whole bordered tile before matching fragments, including old cells.
     * Require the real 16-row toolbar border; other screens are unaffected. */
    private boolean[] disabledToolbar(boolean[] pixels, int sw, int sh) {
        boolean[] blocked = new boolean[pixels.length];
        if (sh < 16 || toolbarLabels.get('F') == null) return blocked;
        for (int x = 0; x < sw; ++x) if (!pixels[15 * sw + x]) return blocked;
        int left = -1;
        for (int right = 0; right < sw; ++right) {
            if (!pixels[7 * sw + right] || !pixels[13 * sw + right] || !pixels[14 * sw + right]) continue;
            if (left >= 0 && right - left >= 8) {
                boolean label = false, content = false;
                Glyph f = toolbarLabels.get('F');
                for (int x = left + 1; x + f.width < right && !label; ++x)
                    for (int polarity = 0; polarity < 2 && !label; ++polarity) {
                        if (!exact(new Cell(x, 2, polarity != 0, f), pixels, sw)) continue;
                        for (char digit = '1'; digit <= '8'; ++digit) {
                            Glyph n = toolbarLabels.get(digit);
                            if (n != null && x + f.width + n.width <= right
                                && exact(new Cell(x + f.width, 2, polarity != 0, n), pixels, sw)) { label = true; break; }
                        }
                    }
                for (int y = 2; y <= 12; ++y) for (int x = left + 1; x < right; ++x) content |= pixels[y * sw + x];
                if (content && !label) for (int y = 0; y < 15; ++y)
                    for (int x = left + 1; x < right; ++x) blocked[y * sw + x] = true;
            }
            left = right;
        }
        return blocked;
    }
    private void addToolbarDropdowns(boolean[] pixels, int sw, int sh,
        boolean[] occupied, List<Cell> result) {
        if (sh < 16) return;
        for (int x = 0; x < sw; ++x) if (!pixels[15 * sw + x]) return;
        List<Cell> arrows = new ArrayList<Cell>();
        for (Cell f : result) {
            if (f.glyph.font != 0 || f.glyph.character != 'F' || f.y != 2) continue;
            for (Cell n : result) {
                if (n.glyph.font != 0 || n.glyph.character < '1' || n.glyph.character > '8'
                    || n.y != f.y || n.x != f.x + f.glyph.width || n.inverse != f.inverse) continue;
                Cell arrow = new Cell(n.x + n.glyph.width, f.y + 2, f.inverse, dropdown);
                if (arrow.x + 3 <= sw && !overlaps(arrow, occupied, sw)
                    && !overlaps(arrow, disabledToolbar, sw) && exact(arrow, pixels, sw)) {
                    occupy(arrow, occupied, sw); arrows.add(arrow);
                }
            }
        }
        result.addAll(arrows);
    }

    private void addMathIntegrals(boolean[] pixels, int sw, int sh, boolean[] occupied,
        List<Cell> singles, List<Cell> result, boolean retainedContext) {
        // Pretty print extends this five-column stem between unchanged caps.
        // Its font-table integral is a different, fixed-height bitmap.
        for (int y = 14; y < sh - 20; ++y) for (int x = 0; x <= sw - 5; ++x) for (int polarity = 0; polarity < 2; ++polarity) {
            boolean inverse = polarity != 0;
            if (row(pixels, sw, x, y, 5, inverse) != 2
                || row(pixels, sw, x, y + 1, 5, inverse) != 5) continue;
            int end = y + 2;
            while (end < sh - 14 && row(pixels, sw, x, end, 5, inverse) == 4) ++end;
            if (end < y + 5 || row(pixels, sw, x, end, 5, inverse) != 20
                || row(pixels, sw, x, end + 1, 5, inverse) != 8) continue;
            int h = end - y + 2;
            String key = "integral:" + h;
            Glyph g = delimiters.get(key);
            if (g == null) {
                int[] rows = new int[h]; rows[0] = 2; rows[1] = 5;
                for (int j = 2; j < h - 2; ++j) rows[j] = 4;
                rows[h - 2] = 20; rows[h - 1] = 8;
                g = new Glyph(1, 5, h, specialCharacter(189), rows, true); delimiters.put(key, g);
            }
            Cell integral = new Cell(x, y, inverse, g);
            // An inverse selection may end exactly on the integral's left or
            // top edge. The complete five-column inverse bitmap and selected
            // expression context validate it without requiring exterior ink.
            if (overlaps(integral, occupied, sw)
                || (!inverse && !clearInkBorder(integral, pixels, sw, sh))) continue;
            boolean expression = false;
            for (Cell c : singles) if (c.inverse == inverse && c.x >= x + 5 && c.x <= x + (retainedContext ? 60 : 20)
                && c.y >= y && c.y + c.glyph.height <= y + h + 1
                && (retainedContext || clearInkBorder(c, pixels, sw, sh))) { expression = true; break; }
            if (!expression) continue;
            occupy(integral, occupied, sw); result.add(integral);
        }
    }

    private static boolean exponentialToken(Run run) {
        if (run.font == 0) return false;
        for (int i = 0; i + 2 < run.cells.size(); ++i) {
            Cell e = run.cells.get(i), caret = run.cells.get(i + 1), opening = run.cells.get(i + 2);
            if ((e.glyph.character == specialCharacter(150) || e.glyph.character == 'e')
                && caret.glyph.character == '^' && opening.glyph.character == '('
                && e.x + e.glyph.width == caret.x
                && caret.x + caret.glyph.width == opening.x) return true;
        }
        return false;
    }
    private static boolean homeInputBorders(boolean[] pixels, int sw, int sh) {
        if (sw != 160 || sh != 100) return false;
        for (int x = 0; x < sw; ++x)
            if (!pixels[(sh - 17) * sw + x] || !pixels[(sh - 7) * sw + x]) return false;
        return true;
    }
    private static boolean clearInkBorder(Cell c, boolean[] pixels, int sw, int sh) {
        Glyph g = c.glyph;
        int left = c.x + g.minX, right = c.x + g.maxX;
        int top = c.y + g.minY, bottom = c.y + g.maxY;
        for (int y = top - 1; y <= bottom + 1; ++y) for (int x = left - 1; x <= right + 1; ++x) {
            if (x >= left && x <= right && y >= top && y <= bottom) continue;
            if (x >= 0 && x < sw && y >= 0 && y < sh && pixels[y * sw + x] != c.inverse) return false;
        }
        return true;
    }
    private static boolean confirmedDelimiter(List<Cell> fresh, Cell old) {
        for (Cell c : fresh) if (c.glyph == old.glyph && c.x == old.x && c.y == old.y
            && c.inverse == old.inverse) return true;
        return false;
    }
    private Glyph delimiter(char ch, int height) {
        String key = ch + ":" + height;
        Glyph g = delimiters.get(key);
        if (g == null) {
            int[] rows = new int[height];
            rows[0] = rows[height - 1] = ch == '(' ? 1 : 4;
            rows[1] = rows[height - 2] = 2;
            for (int y = 2; y < height - 2; ++y) rows[y] = ch == '(' ? 4 : 1;
            g = new Glyph(1, 3, height, ch, rows, true);
            delimiters.put(key, g);
        }
        return g;
    }
    private static boolean exact(Cell c, boolean[] pixels, int sw) {
        for (int y = 0; y < c.glyph.height; ++y)
            if (row(pixels, sw, c.x, c.y + y, c.glyph.width, c.inverse) != c.glyph.rows[y]) return false;
        return true;
    }
    private void addMathDelimiters(boolean[] pixels, int sw, int sh, boolean[] occupied, List<Cell> result) {
        List<Cell> candidates = new ArrayList<Cell>();
        // The ROM extends the straight middle of a three-column parenthesis;
        // its two diagonal cap rows are unchanged at every expression height.
        for (int y = 14; y < sh - 18; ++y) for (int x = 0; x <= sw - 3; ++x) for(int polarity=0;polarity<2;polarity++) {
            boolean inverse=polarity!=0;
            int cap = row(pixels, sw, x, y, 3, inverse);
            if (cap != 1 && cap != 4) continue;
            char ch = cap == 1 ? '(' : ')';
            if (row(pixels, sw, x, y + 1, 3, inverse) != 2) continue;
            int end = y + 2, stem = ch == '(' ? 4 : 1;
            while (end < sh - 14 && row(pixels, sw, x, end, 3, inverse) == stem) ++end;
            if (end < y + 5 || row(pixels, sw, x, end, 3, inverse) != 2
                || row(pixels, sw, x, end + 1, 3, inverse) != cap) continue;
            Cell c = new Cell(x, y, inverse, delimiter(ch, end - y + 2));
            if (!overlaps(c, occupied, sw) && (inverse || clearInkBorder(c, pixels, sw, sh)) && exact(c, pixels, sw)) candidates.add(c);
        }
        // Pair matching prevents an isolated curve or graph-like mark from
        // being redrawn. Require actual recognized expression text inside.
        for (Cell left : candidates) {
            if (left.glyph.character != '(') continue;
            Cell right = null;
            for (Cell c : candidates) if (c.glyph.character == ')' && c.inverse==left.inverse && c.y == left.y
                && c.glyph.height == left.glyph.height && c.x > left.x + 3
                && (right == null || c.x < right.x)) right = c;
            if (right == null || overlaps(left, occupied, sw) || overlaps(right, occupied, sw)) continue;
            boolean content = false;
            for (Cell c : result) if (textAnchor(c.glyph.character) && c.inverse==left.inverse
                && c.x >= left.x + 3 && c.x + c.glyph.width <= right.x
                && c.y >= left.y && c.y + c.glyph.height <= left.y + left.glyph.height + 1) { content = true; break; }
            if (!content) continue;
            occupy(left, occupied, sw); occupy(right, occupied, sw);
            result.add(left); result.add(right);
        }
    }
}
