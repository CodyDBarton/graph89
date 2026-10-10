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
    private SharpTextRecognizer recognizer;
    private List<SharpTextRecognizer.Cell> fallback = Collections.emptyList();
    private List<SharpTextRecognizer.Cell> cells = Collections.emptyList();
    private final Paint ink = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Map<SharpTextRecognizer.Glyph, Path> outlines = new HashMap<SharpTextRecognizer.Glyph, Path>();
    private final Paint background = new Paint();
    private boolean attemptedFonts;
    private boolean[] pixels;
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
        fallback = recognizer.recognizeStable(pixels, width, height, fallback);
        cells = recognizer.retained(EmulatorActivity.nativeTiEmuGetRetainedText(pixels), fallback);
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

    void draw(Canvas canvas, Rect destination, int width, int height, int onColor, int offColor) {
        if (!available || pixels == null) return;
        float sx = destination.width() / (float)width, sy = destination.height() / (float)height;
        int outer = canvas.save(); canvas.clipRect(destination);
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
        canvas.restoreToCount(outer);
    }
}
