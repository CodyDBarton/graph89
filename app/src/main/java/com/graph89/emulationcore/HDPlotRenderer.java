package com.graph89.emulationcore;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.Region;

/** Curves from additional ROM evaluations, in unrounded LCD coordinates. */
final class HDPlotRenderer {
    private boolean[] nativePixels;
    private float[] points=new float[0],decorations=new float[0];
    private final byte[] background=new byte[16000];
    private final SharpTextRenderer labelFont=new SharpTextRenderer();
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    void update(int[] screen,int zoom,int width,int height,int on) {
        if(width!=160 || height!=100){points=new float[0];return;}
        boolean[] pixels=new boolean[16000];
        for(int y=0;y<100;y++)for(int x=0;x<160;x++)pixels[y*160+x]=screen[(y*zoom+zoom/2)*width*zoom+x*zoom+zoom/2]==on;
        nativePixels=pixels;
        TIEmuFrameAccess.lock.lock();
        try {
            points=EmulatorActivity.nativeTiEmuGetHDPlot(pixels,background);
            decorations=points!=null&&points.length>0?EmulatorActivity.nativeTiEmuGetHDPlotDecorations():new float[0];
        } finally { TIEmuFrameAccess.lock.unlock(); }
    }
    boolean isSmoothRotating() {
        if(decorations==null)return false;
        for(int i=0;i+3<decorations.length;i+=4)if(Float.isNaN(decorations[i])&&decorations[i+1]==-9&&decorations[i+2]>0)return true;
        return false;
    }
    byte[] overlayMask() { return isActive()?background:null; }
    boolean isActive() { return points!=null && points.length>=8; }
    void draw(Canvas canvas,Rect destination,int on,int off) {
        if(points==null || points.length<8)return;
        int saved=canvas.save();canvas.translate(destination.left,destination.top);
        canvas.scale(destination.width()/160f,destination.height()/100f);
        canvas.clipRect(points[0],points[1],points[2],points[3]);
        // Leave calculator cursors, readouts and popup whitespace visible in
        // the already drawn native LCD/sharp-text layer beneath this graph.
        for(int y=16;y<93;y++)for(int x=0;x<159;) {
            if((background[y*160+x]&2)==0){x++;continue;}
            int left=x;while(x<159 && (background[y*160+x]&2)!=0)x++;
            canvas.clipRect(left,y,x,y+1,Region.Op.DIFFERENCE);
        }
        paint.setStyle(Paint.Style.FILL);paint.setColor(off);paint.setAntiAlias(false);
        canvas.drawRect(points[0],points[1],points[2],points[3],paint);
        Path axes=new Path();for(int y=16;y<93;y++)for(int x=0;x<159;) {
            if((background[y*160+x]&1)==0){x++;continue;}
            int left=x;while(x<159 && (background[y*160+x]&1)!=0)x++;
            axes.addRect(left,y,x,y+1,Path.Direction.CW);
        }
        paint.setColor(on);canvas.drawPath(axes,paint);
        paint.setAntiAlias(true);paint.setStrokeCap(Paint.Cap.ROUND);
        float stroke=240f/destination.width();paint.setStrokeWidth(stroke);
        Path geometry=new Path();
        if(decorations!=null)for(int i=0;i+3<decorations.length;i+=4){
            float x=decorations[i],y=decorations[i+1],u=decorations[i+2],v=decorations[i+3];
            if(Float.isNaN(x)){if(y==-5 || y==-6){paint.setStyle(Paint.Style.FILL);paint.setAntiAlias(true);if(y==-6)canvas.drawRect(u-1.5f,v-1.5f,u+1.5f,v+1.5f,paint);else canvas.drawCircle(u,v,1.0f,paint);}continue;}
            if(x==u&&y==v){paint.setStyle(Paint.Style.FILL);canvas.drawCircle(x,y,stroke/2,paint);}
            else {geometry.moveTo(x,y);geometry.lineTo(u,v);}
        }
        paint.setStyle(Paint.Style.STROKE);canvas.drawPath(geometry,paint);
        boolean surface=false;if(decorations!=null)for(int i=0;i+3<decorations.length;i+=4)if(Float.isNaN(decorations[i])&&decorations[i+1]==-7&&decorations[i+2]==5)surface=true;
        Path curve=new Path();boolean previous=false;double previousX=0,previousY=0;
        for(int i=4;i+1<points.length;i+=2){float x=points[i]+0.5f,y=points[i+1]+0.5f;
            if(Float.isNaN(x)||Float.isNaN(y)||Float.isInfinite(x)||Float.isInfinite(y)){previous=false;continue;}
            boolean crossesPole=!surface && previous && ((previousY<16 && y>93)||(previousY>93 && y<16));
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
        // Reconstruct the verified ROM cursor at its full bitmap centre, even
        // when overlap with a curve hides its native silhouette.
        boolean vectorCursor=false;
        int overlaySave=canvas.save();canvas.translate(destination.left,destination.top);
        canvas.scale(destination.width()/160f,destination.height()/100f);
        canvas.clipRect(points[0],points[1],points[2],points[3]);
        if(decorations!=null)for(int i=0;i+3<decorations.length;i+=4)if(Float.isNaN(decorations[i])) {
            int kind=(int)decorations[i+1];float x=decorations[i+2],y=decorations[i+3];
            if(kind==-2 || kind==-4){vectorCursor=true;}else if(kind==-1 || kind==-3) {
                vectorCursor=true;int cursorSave=canvas.save();canvas.clipRect(0,16,159,83);float radius=kind==-3?7.5f:3,extent=kind==-3?10:5;Path cursor=new Path();cursor.addCircle(x,y,radius,Path.Direction.CW);
                cursor.moveTo(x-extent,y);cursor.lineTo(x+extent,y);cursor.moveTo(x,y-extent);cursor.lineTo(x,y+extent);
                paint.setAntiAlias(true);paint.setStyle(Paint.Style.STROKE);paint.setStrokeCap(Paint.Cap.BUTT);
                paint.setColor(off);paint.setStrokeWidth(2);canvas.drawPath(cursor,paint);
                paint.setColor(on);paint.setStrokeWidth(0.8f);canvas.drawPath(cursor,paint);canvas.restoreToCount(cursorSave);
            }else if(kind>=48 && kind<=57)labelFont.drawPlotNumber(canvas,kind,x,y,on,off);
        }
        canvas.restoreToCount(overlaySave);
        // Unknown cursor shapes keep their actual native appearance.
        if(nativePixels!=null && !vectorCursor) {
            paint.setStyle(Paint.Style.FILL);paint.setAntiAlias(false);
            float sx=destination.width()/160f,sy=destination.height()/100f;
            for(int y=16;y<83;y++)for(int x=0;x<159;x++)if((background[y*160+x]&4)!=0) {
                paint.setColor(nativePixels[y*160+x]?on:off);
                canvas.drawRect(destination.left+x*sx,destination.top+y*sy,
                    destination.left+(x+1)*sx,destination.top+(y+1)*sy,paint);
            }
        }
    }
}
