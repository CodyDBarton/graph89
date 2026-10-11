package com.graph89.emulationcore;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Path;
import android.graphics.Matrix;
import android.graphics.Region;
import android.graphics.Typeface;
import java.util.HashMap;
import java.util.Map;
import java.util.Collections;
import java.util.List;

/** Exact ROM recognition with the approved smooth font; unmatched pixels stay original. */
final class SharpTextRenderer {
    boolean compact;
    private int[] retained;
    private SharpTextRecognizer recognizer;
    private List<SharpTextRecognizer.Cell> fallback = Collections.emptyList();
    private List<SharpTextRecognizer.Cell> cells = Collections.emptyList();
    private final Paint ink = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Map<SharpTextRecognizer.Glyph, Path> outlines = new HashMap<SharpTextRecognizer.Glyph, Path>();
    private final Paint background = new Paint();
    private boolean attemptedFonts;
    private boolean[] pixels;
    private int[] cursor;
    private final boolean available;
    private final RectF familyBounds = new RectF();

    private static Typeface approvedTypeface;
    static void initialize(Context context) {
        if (approvedTypeface == null)
            approvedTypeface = Typeface.createFromAsset(context.getAssets(), "fonts/Graph89HD.ttf");
    }

    SharpTextRenderer() {
        boolean loaded = false;
        try {
            if (approvedTypeface == null) throw new IllegalStateException("Font not initialized");
            ink.setTypeface(approvedTypeface);
            ink.setTextSize(2048);
            // Use one scale for the whole face, including its full descenders and
            // round-capital overshoot. Never squeeze a character in one direction.
            for (char c = 33; c < 127; ++c) {
                Path path = new Path(); RectF bounds = new RectF();
                String text = String.valueOf(c);
                ink.getTextPath(text, 0, 1, 0, 0, path);
                path.computeBounds(bounds, true); familyBounds.union(bounds);
            }
            loaded = !familyBounds.isEmpty();
        } catch (RuntimeException missingPrivateFont) {
            // Until font initialization, leave the real LCD intact.
        }
        available = loaded;
    }

    void update(int[] screen, int zoom, int width, int height, int onColor) {
        if (!available) return;
        if (!attemptedFonts) {
            byte[] fonts = EmulatorActivity.nativeTiEmuGetFontTemplates();
            if (fonts != null) {
                if (fonts.length != 0) recognizer = new SharpTextRecognizer(fonts);
                attemptedFonts = true;
            }
        }
        if (recognizer == null) { cells = Collections.emptyList(); return; }
        pixels = new boolean[width * height];
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x)
                pixels[y * width + x] = screen[(y * zoom + zoom / 2) * width * zoom + x * zoom + zoom / 2] == onColor;
        int[] packets=EmulatorActivity.nativeTiEmuGetRetainedText(pixels);
        retained=packets;
        cursor=SharpTextRecognizer.cursor(packets);
        pixels=SharpTextRecognizer.withoutCursor(pixels,packets);
        fallback = recognizer.recognizeStable(pixels, width, height, fallback);
        cells = recognizer.retained(packets, fallback);
    }

    private Path outline(SharpTextRecognizer.Glyph g) {
        Path cached = outlines.get(g);
        if (cached != null) return cached;
        if (g.character == SharpTextRecognizer.TOOLBAR_DROPDOWN) {
            Path triangle = new Path(); triangle.moveTo(0, 0);
            triangle.lineTo(3, 0); triangle.lineTo(1.5f, 2); triangle.close();
            outlines.put(g, triangle); return triangle;
        }
        if (g.character == SharpTextRecognizer.specialCharacter(18)) {
            // Approved Catalog pointer: use its original ink rectangle in each
            // ROM font size, leaving the character's spacing/padding intact.
            Path triangle = new Path();
            triangle.moveTo(g.minX, g.minY);
            triangle.lineTo(g.maxX + 1, (g.minY + g.maxY + 1) / 2f);
            triangle.lineTo(g.minX, g.maxY + 1); triangle.close();
            outlines.put(g, triangle); return triangle;
        }
        if (g.character == SharpTextRecognizer.specialCharacter(180)) {
            // The ROM's raised -1 is one glyph. Each font size has its own
            // approved composition, already laid out at 200 units per pixel.
            String text = String.valueOf((char)(0xe300 + g.font));
            Path path = new Path(); ink.getTextPath(text, 0, 1, 0, 0, path);
            Matrix matrix = new Matrix(); matrix.setScale(1f / 200, 1f / 200);
            matrix.postTranslate(0, 10); path.transform(matrix);
            outlines.put(g, path); return path;
        }
        String text = String.valueOf(g.character);
        Path path = new Path();
        ink.getTextPath(text, 0, 1, 0, 0, path);
        RectF bounds = new RectF(); path.computeBounds(bounds, true);
        float scale = (g.height - 0.10f) / familyBounds.height();
        // Only the small ROM font is proportional. Very narrow cells may need
        // a smaller uniform size, keeping stroke geometry and aspect intact.
        if (bounds.width() > 0) scale = Math.min(scale, (g.width - 0.10f) / bounds.width());
        float left = (g.width - ink.measureText(text) * scale) / 2;
        float baseline = 0.05f - familyBounds.top * scale;
        Matrix matrix = new Matrix();
        if (g.mathDelimiter && !bounds.isEmpty()) {
            // Pretty-print delimiters grow with their enclosed expression.
            // Size the approved parenthesis/integral to its exact ROM ink rectangle.
            float sx = (g.width - 0.10f) / bounds.width();
            float sy = (g.height - 0.10f) / bounds.height();
            matrix.setScale(sx, sy);
            matrix.postTranslate(0.05f - bounds.left * sx, 0.05f - bounds.top * sy);
        } else {
            matrix.setScale(scale, scale);
            matrix.postTranslate(left, baseline);
        }
        path.transform(matrix);
        outlines.put(g, path);
        return path;
    }

    private void drawCompact(Canvas canvas,Rect destination,float sx,float sy,SharpTextRecognizer.CompactScene scene,int on,int off) {
        int saved=canvas.save();canvas.translate(destination.left,destination.top);canvas.scale(sx,sy);
        background.setColor(off);
        if(scene.body)canvas.drawRect(0,16,160,83,background);
        if(scene.input)canvas.drawRect(0,84,160,93,background);
        if(scene.yEditor) {
            boolean[] remaining=pixels.clone();
            for(double[] r:scene.eraseRects) {
                int x0=Math.max(0,(int)r[0]),x1=Math.min(160,(int)Math.ceil(r[0]+r[2]));
                int y0=Math.max(16,(int)r[1]),y1=Math.min(83,(int)Math.ceil(r[1]+r[3]));
                for(int y=y0;y<y1;y++)for(int x=x0;x<x1;x++)remaining[y*160+x]=r[4]!=0;
            }
            Path raster=new Path();
            for(int y=16;y<83;y++)for(int x=0;x<160;) {
                if(!remaining[y*160+x]){x++;continue;}
                int left=x;while(x<160 && remaining[y*160+x])x++;
                raster.addRect(left*0.72f,16+(y-16)*0.72f,x*0.72f,16+(y-15)*0.72f,Path.Direction.CW);
            }
            background.setColor(on);canvas.drawPath(raster,background);
        }else if(scene.body) {
            background.setColor(on);
            for(int y=16;y<83;y++)for(int x=0;x<6;x++)if(pixels[y*160+x])canvas.drawRect(x,83+(y-83)*0.72f,x+1,83+(y-82)*0.72f,background);
        }
        int bodyClip=canvas.save();canvas.clipRect(0,scene.yEditor?21.04f:16,160,83);background.setColor(on);
        for(double[] r:scene.inverseRects)canvas.drawRect((float)r[0],(float)r[1],(float)(r[0]+r[2]),(float)(r[1]+r[3]),background);
        canvas.restoreToCount(bodyClip);
        for(SharpTextRecognizer.CompactItem item:scene.items)if(item.inverse && item.glyph!=null && item.scale==0.8) {
            int clip=canvas.save();canvas.clipRect(0,item.scale==0.8?84:(float)item.clipTop,160,item.scale==0.8?93:83);
            background.setColor(on);
            canvas.drawRect((float)item.x-0.5f,(float)item.y,(float)(item.x+(item.scale==0.8?4.5:(item.glyph.width+1)*item.scale)-0.5),(float)(item.y+item.glyph.height*item.scale),background);
            canvas.restoreToCount(clip);
        }
        for(SharpTextRecognizer.CompactItem item:scene.items) {
            int clip=canvas.save();canvas.clipRect(0,item.scale==0.8?84:(float)item.clipTop,160,item.scale==0.8?93:83);
            ink.setColor(item.inverse?off:on);
            if(item.glyph!=null) {
                SharpTextRecognizer.Glyph g=item.glyph;canvas.translate((float)item.x,(float)item.y);canvas.scale((float)item.scale,(float)item.scale);
                if(g.character!=0)canvas.drawPath(outline(g),ink);
                else for(int y=0;y<g.height;y++)for(int x=0;x<g.width;x++)if((g.rows[y]&(1<<(g.width-x-1)))!=0)canvas.drawRect(x,y,x+1,y+1,ink);
            }else if(item.attribute!=0) {
                ink.setStrokeWidth((float)item.scale);ink.setStrokeCap(Paint.Cap.SQUARE);
                canvas.drawLine((float)(item.x+item.scale/2),(float)(item.y+item.scale/2),(float)(item.x1+item.scale/2),(float)(item.y1+item.scale/2),ink);
            }
            canvas.restoreToCount(clip);
        }
        if(scene.cursorX!=null && cursor!=null) {
            ink.setColor(on);
            for(int y=0;y<8;y++)if((cursor[1]&(1<<y))!=0)canvas.drawRect(scene.cursorX.floatValue(),85.8f+y*0.8f,scene.cursorX.floatValue()+0.6f,85.8f+(y+1)*0.8f,ink);
        }
        canvas.restoreToCount(saved);
    }
    void draw(Canvas canvas, Rect destination, int width, int height, int onColor, int offColor) {
        if (!available || pixels == null) return;
        float sx = destination.width() / (float)width, sy = destination.height() / (float)height;
        int outer = canvas.save(); canvas.clipRect(destination);
        if(cursor!=null)for(int y=0;y<8;y++)for(int x=0;x<2;x++) {
            int px=cursor[0]+x,py=85+y;
            background.setColor(pixels[py*width+px]?onColor:offColor);
            canvas.drawRect(destination.left+px*sx,destination.top+py*sy,
                destination.left+(px+1)*sx,destination.top+(py+1)*sy,background);
        }
        for (SharpTextRecognizer.Cell cell : cells) {
            SharpTextRecognizer.Glyph g = cell.glyph;
            if (g.character == 0 || g.maxX < g.minX) continue;
            int savedClip=canvas.save();
            canvas.clipRect(destination.left+cell.clipLeft*sx,destination.top+cell.clipTop*sy,
                destination.left+cell.clipRight*sx,destination.top+cell.clipBottom*sy);
            float left = destination.left + cell.x * sx, top = destination.top + cell.y * sy;
            // Clear only the original glyph ink bounds. Padding holds the cursor.
            background.setColor(cell.inverse ? onColor : offColor);
            canvas.drawRect(left + g.minX * sx, top + g.minY * sy,
                left + (g.maxX + 1) * sx, top + (g.maxY + 1) * sy, background);
            ink.setColor(cell.inverse ? offColor : onColor);
            int saved = canvas.save();
            canvas.translate(left, top); canvas.scale(sx, sy);
            canvas.clipRect(0, 0, g.width, g.height);
            // The smooth face can extend into originally blank padding. Preserve
            // any live cursor pixels there, without changing the glyph's shape
            // from frame to frame or erasing the cursor.
            for (int y = Math.max(0,cell.clipTop-cell.y); y < Math.min(g.height,cell.clipBottom-cell.y); ++y) for (int x = Math.max(0,cell.clipLeft-cell.x); x < Math.min(g.width,cell.clipRight-cell.x); ++x) {
                if (x >= g.minX && x <= g.maxX && y >= g.minY && y <= g.maxY) continue;
                if (pixels[(cell.y + y) * width + cell.x + x] != cell.inverse)
                    canvas.clipRect(x, y, x + 1, y + 1, Region.Op.DIFFERENCE);
            }
            canvas.drawPath(outline(g), ink);
            canvas.restoreToCount(saved);canvas.restoreToCount(savedClip);
        }
        SharpTextRecognizer.CompactScene scene=compact && recognizer!=null?recognizer.compactScene(retained):null;
        if(scene!=null)drawCompact(canvas,destination,sx,sy,scene,onColor,offColor);
        if(cursor!=null && (scene==null || !scene.input)) {
            ink.setColor(onColor);
            for(int y=0;y<8;y++)if((cursor[1]&(1<<y))!=0)
                canvas.drawRect(destination.left+(cursor[0]+0.7f)*sx,destination.top+(85+y)*sy,
                    destination.left+(cursor[0]+1.3f)*sx,destination.top+(86+y)*sy,ink);
        }
        canvas.restoreToCount(outer);
    }
}
