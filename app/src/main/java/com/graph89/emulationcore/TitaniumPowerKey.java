package com.graph89.emulationcore;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.Shader;
import android.graphics.Typeface;

/** Titanium portrait ON/OFF artwork, matching the screenshot-based iOS drawing. */
final class TitaniumPowerKey {
    private TitaniumPowerKey() {}

    static void draw(Canvas canvas, String imagePath, Rect destination) {
        if (!"portrait/ti89tclassic/skin.jpg".equals(imagePath)) return;
        canvas.save();
        canvas.translate(destination.left, destination.top);
        canvas.scale(destination.width() / 635f, destination.height() / 1014f);

        // Preserve the photographed key contour and rim while covering EMU.
        Path face = new Path();
        face.moveTo(43, 878);
        face.cubicTo(55, 874, 92, 877, 113, 882);
        face.cubicTo(120, 883, 123, 887, 122, 895);
        face.lineTo(122, 932);
        face.cubicTo(123, 944, 117, 950, 105, 950);
        face.cubicTo(80, 950, 51, 932, 43, 907);
        face.cubicTo(37, 893, 37, 883, 43, 878);
        face.close();
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setShader(new LinearGradient(83, 877, 83, 950,
                new int[] {Color.rgb(87, 87, 87), Color.rgb(102, 102, 102), Color.rgb(117, 117, 117)},
                new float[] {0f, 0.55f, 1f}, Shader.TileMode.CLAMP));
        canvas.drawPath(face, paint);
        paint.setShader(null);
        paint.setTypeface(Typeface.create("sans-serif-condensed", Typeface.BOLD));
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setColor(Color.rgb(247, 247, 247));
        paint.setTextSize(24);
        drawTextAtTop(canvas, "ON", 84, 895, paint);
        paint.setColor(Color.rgb(166, 214, 230));
        paint.setTextSize(18);
        drawTextAtTop(canvas, "OFF", 92, 851, paint);
        canvas.restore();
    }

    private static void drawTextAtTop(Canvas canvas, String text, float centerX, float top, Paint paint) {
        canvas.drawText(text, centerX, top - paint.getFontMetrics().ascent, paint);
    }
}
