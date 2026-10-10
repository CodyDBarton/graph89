package com.graph89.emulationcore;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

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
