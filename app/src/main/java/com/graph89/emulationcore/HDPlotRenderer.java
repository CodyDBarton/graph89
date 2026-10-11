package com.graph89.emulationcore;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;

/** Curves from additional ROM evaluations, in unrounded LCD coordinates. */
final class HDPlotRenderer {
    private float[] points=new float[0],decorations=new float[0];
    private final byte[] background=new byte[16000];
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    void update(int[] screen,int zoom,int width,int height,int on) {
        if(width!=160 || height!=100){points=new float[0];return;}
        boolean[] pixels=new boolean[16000];
        for(int y=0;y<100;y++)for(int x=0;x<160;x++)pixels[y*160+x]=screen[(y*zoom+zoom/2)*width*zoom+x*zoom+zoom/2]==on;
        TIEmuFrameAccess.lock.lock();
        try {
            points=EmulatorActivity.nativeTiEmuGetHDPlot(pixels,background);
            decorations=points!=null&&points.length>0?EmulatorActivity.nativeTiEmuGetHDPlotDecorations():new float[0];
        } finally { TIEmuFrameAccess.lock.unlock(); }
    }
    boolean isActive() { return points!=null && points.length>=8; }
    void draw(Canvas canvas,Rect destination,int on,int off) {
        if(points==null || points.length<8)return;
        int saved=canvas.save();canvas.translate(destination.left,destination.top);
        canvas.scale(destination.width()/160f,destination.height()/100f);
        canvas.clipRect(points[0],points[1],points[2],points[3]);
        paint.setStyle(Paint.Style.FILL);paint.setColor(off);paint.setAntiAlias(false);
        canvas.drawRect(points[0],points[1],points[2],points[3],paint);
        Path axes=new Path();for(int y=16;y<93;y++)for(int x=0;x<159;) {
            if(background[y*160+x]==0){x++;continue;}
            int left=x;while(x<159 && background[y*160+x]!=0)x++;
            axes.addRect(left,y,x,y+1,Path.Direction.CW);
        }
        paint.setColor(on);canvas.drawPath(axes,paint);
        paint.setAntiAlias(true);paint.setStrokeCap(Paint.Cap.ROUND);
        float stroke=240f/destination.width();paint.setStrokeWidth(stroke);
        Path geometry=new Path();
        if(decorations!=null)for(int i=0;i+3<decorations.length;i+=4){
            float x=decorations[i],y=decorations[i+1],u=decorations[i+2],v=decorations[i+3];
            if(x==u&&y==v){paint.setStyle(Paint.Style.FILL);canvas.drawCircle(x,y,stroke/2,paint);}
            else {geometry.moveTo(x,y);geometry.lineTo(u,v);}
        }
        paint.setStyle(Paint.Style.STROKE);canvas.drawPath(geometry,paint);
        Path curve=new Path();boolean previous=false;double previousX=0,previousY=0;
        for(int i=4;i+1<points.length;i+=2){float x=points[i]+0.5f,y=points[i+1]+0.5f;
            if(Float.isNaN(x)||Float.isNaN(y)||Float.isInfinite(x)||Float.isInfinite(y)){previous=false;continue;}
            boolean crossesPole=previous && ((previousY<16 && y>93)||(previousY>93 && y<16));
            if(previous && !crossesPole){
                double dx=x-previousX,dy=y-previousY,lo=0,hi=1;boolean valid=true;
                double[] d={-dx,dx,-dy,dy},q={previousX-points[0],points[2]-previousX,previousY-points[1],points[3]-previousY};
                for(int k=0;k<4;k++){
                    if(d[k]==0){if(q[k]<0)valid=false;continue;}
                    double t=q[k]/d[k];if(d[k]<0)lo=Math.max(lo,t);else hi=Math.min(hi,t);
                }
                if(valid && lo<=hi){
                    curve.moveTo((float)(previousX+lo*dx),(float)(previousY+lo*dy));
                    curve.lineTo((float)(previousX+hi*dx),(float)(previousY+hi*dy));
                }
            }
            previous=true;previousX=x;previousY=y;
        }
        paint.setAntiAlias(true);paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(240f/destination.width());paint.setStrokeJoin(Paint.Join.ROUND);paint.setStrokeCap(Paint.Cap.ROUND);
        canvas.drawPath(curve,paint);canvas.restoreToCount(saved);
    }
}
