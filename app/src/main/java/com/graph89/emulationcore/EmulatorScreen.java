/*
 *   Graph89 - Emulator for Android
 *  
 *	 Copyright (C) 2012-2013  Dritan Hashorva
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.

 *   You should have received a copy of the GNU General Public License
 *   along with this program.  If not, see <http://www.gnu.org/licenses/>
 */

package com.graph89.emulationcore;

import java.io.IOException;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;

import com.graph89.common.SkinBase;
import com.graph89.common.CalculatorConfiguration;
import com.graph89.common.CalculatorTypes;
import com.graph89.common.Util;

public class EmulatorScreen
{
	public static Object				ScreenChangeLock		= new Object();
	public static EngineScreenParams	EngineScreenParams		= new EngineScreenParams();

	public Rect							DestinationRectangle	= new Rect();

	public ScaledBitmap					ScreenBitmap			= null;

	private SkinBase					mParentSkinBase			= null;
	private Boolean						mIntegerZoom			= false;

	public int							Zoom					= 1;
	public boolean						IsFullScreen			= false;

	private volatile int[]				ScreenData;
	private volatile byte[]				Flags;												//b[0] screen_off, b[1] is_busy

	private int							mZoomedScreenWidth		= 0;
	private int							mZoomedScreenHeight		= 0;

	public int							mRawScreenWidth			= 0;
	public int							mRawScreenHeight		= 0;
	private Paint						mDrawingPaint			= null;

	private volatile boolean						isBusy					= false;
	private volatile boolean						isScreenOff				= false;
	private SharpTextRenderer sharpText;
	private HDPlotRenderer hdPlot;
    // Only completed frames are shared with Canvas. Preparation owns the spare
    // buffers and never holds the UI's ScreenChangeLock.
    private final Object preparationLock = new Object();
    private int[] spareData;
    private int frameZoom=1;
    private SharpTextRenderer spareSharpText;
    private HDPlotRenderer spareHDPlot;

	public int							CRC						= 0;
	private int							cntr					= 0;

	public static class EngineScreenParams
	{
		int	RawWidth	= 0;
		int	RawHeight	= 0;
		int	Zoom		= 0;

		public void Reset()
		{
			RawWidth = 0;
			RawHeight = 0;
			Zoom = 0;
		}
	}

	public EmulatorScreen(SkinBase parent, Rect destinationRectangle, boolean keepNativeAspectRatio, boolean isFullScreen) throws IOException
	{
		mParentSkinBase = parent;
		DestinationRectangle = destinationRectangle;
		IsFullScreen = isFullScreen;

		mRawScreenWidth = mParentSkinBase.CalculatorInfo.ScreenWidth;
		mRawScreenHeight = mParentSkinBase.CalculatorInfo.ScreenHeight;

		if (keepNativeAspectRatio)
		{
			float ar = ((float) mParentSkinBase.CalculatorInfo.ScreenWidth) / mParentSkinBase.CalculatorInfo.ScreenHeight;

			int destinationWidth = DestinationRectangle.right - DestinationRectangle.left;
			int destinationHeight = DestinationRectangle.bottom - DestinationRectangle.top;

			int newHeight = (int) (destinationWidth / ar);

			if (newHeight > destinationHeight)
			{
				int newWidth = (int) (destinationHeight * ar);
				DestinationRectangle.left = (DestinationRectangle.left + DestinationRectangle.right) / 2 - newWidth / 2;
				DestinationRectangle.right = DestinationRectangle.left + newWidth;
			}
			else
			{
				DestinationRectangle.top = (DestinationRectangle.bottom + DestinationRectangle.top) / 2 - newHeight / 2;
				DestinationRectangle.bottom = DestinationRectangle.top + newHeight;
			}
		}

		int destinationWidth = DestinationRectangle.right - DestinationRectangle.left;
		int destinationHeight = DestinationRectangle.bottom - DestinationRectangle.top;

		mIntegerZoom = destinationWidth % mRawScreenWidth == 0;

		float zoomf = ((float) destinationWidth) / mRawScreenWidth;

		Zoom = destinationWidth / mRawScreenWidth;

		int diff = (int) Math.max(Math.abs(destinationWidth - Math.floor(zoomf) * mRawScreenWidth), Math.abs(destinationHeight - Math.floor(zoomf) * mRawScreenHeight));

		// try at best to use an integer zoom. tolerance 20px
		if (mIntegerZoom == false && diff < 20)
		{
			mIntegerZoom = true;

			Zoom = (int) Math.floor(zoomf);

			int width = mRawScreenWidth * Zoom;
			int height = mRawScreenHeight * Zoom;

			int centerx = (DestinationRectangle.left + DestinationRectangle.right) / 2;
			int centery = (DestinationRectangle.top + DestinationRectangle.bottom) / 2;

			Rect newRect = new Rect();
			newRect.top = centery - height / 2;
			newRect.bottom = newRect.top + height;

			newRect.left = centerx - width / 2;
			newRect.right = newRect.left + width;

			DestinationRectangle = newRect;
		}

		if (!mIntegerZoom)
		{
			mDrawingPaint = Util.FilteredPaint;
			Zoom = (int) Math.ceil(zoomf);
		}

		mZoomedScreenWidth = mRawScreenWidth * Zoom;
		mZoomedScreenHeight = mRawScreenHeight * Zoom;

		ScreenBitmap = new ScaledBitmap();
		ScreenBitmap.BitmapObj = Bitmap.createBitmap(mZoomedScreenWidth, mZoomedScreenHeight, Bitmap.Config.ARGB_8888);
		ScreenBitmap.BitmapRectangle = new Rect(0, 0, mZoomedScreenWidth, mZoomedScreenHeight);

		ScreenData = new int[mZoomedScreenWidth * mZoomedScreenHeight];
        frameZoom=Zoom;

		Flags = new byte[6];
	}

	public EmulatorScreen(SkinBase parent)
	{
		mParentSkinBase = parent;
		IsFullScreen = true;
		DestinationRectangle = new Rect(0, 0, EmulatorActivity.AndroidDeviceScreenDimension.Width, EmulatorActivity.AndroidDeviceScreenDimension.Height);

		mRawScreenWidth = mParentSkinBase.CalculatorInfo.ScreenWidth;
		mRawScreenHeight = mParentSkinBase.CalculatorInfo.ScreenHeight;

		int destinationWidth = DestinationRectangle.right - DestinationRectangle.left;
		int destinationHeight = DestinationRectangle.bottom - DestinationRectangle.top;

		int horizontalZoom = destinationWidth / mRawScreenWidth;
		int verticalZoom = destinationHeight / mRawScreenHeight;

		Zoom = Math.min(horizontalZoom, verticalZoom);

		mIntegerZoom = true;

		mZoomedScreenWidth = mRawScreenWidth * Zoom;
		mZoomedScreenHeight = mRawScreenHeight * Zoom;

		ScreenBitmap = new ScaledBitmap();
		ScreenBitmap.BitmapObj = Bitmap.createBitmap(mZoomedScreenWidth, mZoomedScreenHeight, Bitmap.Config.ARGB_8888);
		ScreenBitmap.BitmapRectangle = new Rect(0, 0, mZoomedScreenWidth, mZoomedScreenHeight);

		ScreenData = new int[mZoomedScreenWidth * mZoomedScreenHeight];
        frameZoom=Zoom;

		Flags = new byte[6];
	}

    public void refresh() {
        synchronized(preparationLock) {
            long started=System.nanoTime();
            // HD is composited as vectors at display resolution. Transfer the
            // original LCD once; Canvas scales its raster background without
            // duplicating every pixel into a large JNI/bitmap buffer.
            int bufferZoom=useHDPlot()?1:Zoom;
            boolean sharp=useSharpText(),hd=useHDPlot();
            if(spareData==null || spareData.length!=mRawScreenWidth*mRawScreenHeight*bufferZoom*bufferZoom)
                spareData=new int[mRawScreenWidth*mRawScreenHeight*bufferZoom*bufferZoom];
            byte[] flags=new byte[6];
            int newCRC;
            boolean changed;
            ++cntr;
            TIEmuFrameAccess.lock.lock();
            try {
                EmulatorActivity.nativeTiEmuRetainedTextEnable(sharp);
                EmulatorActivity.nativeTiEmuHDPlotEnable(hd);
                if(EngineScreenParams.RawHeight!=mRawScreenHeight || EngineScreenParams.RawWidth!=mRawScreenWidth || EngineScreenParams.Zoom!=bufferZoom)
                    EmulatorActivity.TiEmuSetScreenParams(this,bufferZoom);
                newCRC=EmulatorActivity.nativeReadEmulatedScreen(flags);
                // Extra HD samples can advance without changing native raster
                // pixels. Poll every frame while BUSY, including its final frame;
                // a completed unchanged screen needs no continuous redraw.
                changed=CRC!=newCRC || cntr%40==0 || (hd && (flags[1]!=0 || isBusy || hdPlot==null));
                if(changed) {
                    EmulatorActivity.nativeGetEmulatedScreen(spareData);
                    if(hd && flags[0]==0) {
                        if(spareHDPlot==null)spareHDPlot=new HDPlotRenderer();
                        spareHDPlot.update(spareData,bufferZoom,mRawScreenWidth,mRawScreenHeight,mParentSkinBase.LCDPixelON);
                    } else spareHDPlot=null;
                }
            } finally { TIEmuFrameAccess.lock.unlock(); }
            long captured=System.nanoTime();
            if(changed) {
                if(sharp && flags[0]==0) {
                    if(spareSharpText==null)spareSharpText=new SharpTextRenderer();
                    spareSharpText.compact=EmulatorActivity.ActiveInstance.Configuration.CompactLayout;
                    spareSharpText.update(spareData,bufferZoom,mRawScreenWidth,mRawScreenHeight,mParentSkinBase.LCDPixelON,
                        hd && spareHDPlot!=null && spareHDPlot.isActive());
                } else spareSharpText=null;
                // Canvas can finish drawing the old frame while we prepare this
                // one. Swap all its components together, then reuse the old frame.
                synchronized(ScreenChangeLock) {
                    int[] oldData=ScreenData;ScreenData=spareData;spareData=oldData;
                    SharpTextRenderer oldSharp=sharpText;sharpText=spareSharpText;spareSharpText=oldSharp;
                    HDPlotRenderer oldPlot=hdPlot;hdPlot=spareHDPlot;spareHDPlot=oldPlot;
                    frameZoom=bufferZoom;
                    CRC=newCRC;
                    isScreenOff=flags[0]!=0;isBusy=flags[1]!=0;
                }
                EmulatorActivity.UIStateManagerObj.EmulatorViewIntstance.postInvalidateOnAnimation();
            } else {
                isScreenOff=flags[0]!=0;isBusy=flags[1]!=0;
            }
            long done=System.nanoTime();
            if(done-started>100_000_000L)
                android.util.Log.w("Graph89Frame","Slow preparation: capture="+(captured-started)/1e6+"ms text/publish="+(done-captured)/1e6+"ms");
        }
    }

	public boolean isBusy()
	{
		return isBusy && !isScreenOff();
	}

	public boolean isScreenOff()
	{
		return isScreenOff;
	}

	public Bitmap getScreenShot()
	{
		synchronized (preparationLock)
		{
            TIEmuFrameAccess.lock.lock();
            try {
            EngineScreenParams.RawWidth=mRawScreenWidth;
            EngineScreenParams.RawHeight=mRawScreenHeight;
			EngineScreenParams.Zoom = 3;

			EmulatorActivity.nativeUpdateScreenZoom(EngineScreenParams.Zoom);

			byte[] flags = new byte[6];

			EmulatorActivity.nativeReadEmulatedScreen(flags);

			int[] data = new int[EngineScreenParams.RawWidth * EngineScreenParams.RawHeight * EngineScreenParams.Zoom * EngineScreenParams.Zoom];

			EmulatorActivity.nativeGetEmulatedScreen(data);

			Bitmap screenshotBitmap = Bitmap.createBitmap(EngineScreenParams.RawWidth * EngineScreenParams.Zoom, EngineScreenParams.RawHeight * EngineScreenParams.Zoom, Bitmap.Config.ARGB_8888);

			screenshotBitmap.setPixels(data, 0, screenshotBitmap.getWidth(), 0, 0, screenshotBitmap.getWidth(), screenshotBitmap.getHeight());
			if (useSharpText() && flags[0] == 0)
			{
				SharpTextRenderer renderer = new SharpTextRenderer();
				renderer.compact = EmulatorActivity.ActiveInstance.Configuration.CompactLayout;
				renderer.update(data, EngineScreenParams.Zoom, EngineScreenParams.RawWidth, EngineScreenParams.RawHeight, mParentSkinBase.LCDPixelON);
				renderer.draw(new Canvas(screenshotBitmap), new Rect(0, 0, screenshotBitmap.getWidth(), screenshotBitmap.getHeight()),
					EngineScreenParams.RawWidth, EngineScreenParams.RawHeight, mParentSkinBase.LCDPixelON, mParentSkinBase.LCDPixelOFF);
			}

            if(useHDPlot() && flags[0]==0){
                HDPlotRenderer renderer=new HDPlotRenderer();
                renderer.update(data,EngineScreenParams.Zoom,EngineScreenParams.RawWidth,EngineScreenParams.RawHeight,mParentSkinBase.LCDPixelON);
                renderer.draw(new Canvas(screenshotBitmap),new Rect(0,0,screenshotBitmap.getWidth(),screenshotBitmap.getHeight()),mParentSkinBase.LCDPixelON,mParentSkinBase.LCDPixelOFF);
            }
			return screenshotBitmap;
            } finally { TIEmuFrameAccess.lock.unlock(); }
		}
	}

    boolean useHDPlot(){
        if(EmulatorActivity.ActiveInstance==null)return false;
        CalculatorConfiguration c=EmulatorActivity.ActiveInstance.Configuration;
        return c.HDPlot && !c.EnableGrayScale && !c.UseLCDGrid && EmulatorActivity.ActiveInstance.CalculatorType==CalculatorTypes.TI89T;
    }
	private boolean useSharpText()
	{
		if (EmulatorActivity.ActiveInstance == null) return false;
		CalculatorConfiguration configuration = EmulatorActivity.ActiveInstance.Configuration;
		int type = EmulatorActivity.ActiveInstance.CalculatorType;
		return configuration.SharpText && !configuration.EnableGrayScale && !configuration.UseLCDGrid
			&& (type == CalculatorTypes.TI89 || type == CalculatorTypes.TI89T);
	}

	public void drawScreen(Canvas canvas)
	{
		synchronized (EmulatorScreen.ScreenChangeLock)
		{
            int bufferWidth=mRawScreenWidth*frameZoom,bufferHeight=mRawScreenHeight*frameZoom;
            if(ScreenBitmap.BitmapObj.getWidth()!=bufferWidth || ScreenBitmap.BitmapObj.getHeight()!=bufferHeight) {
                ScreenBitmap.BitmapObj=Bitmap.createBitmap(bufferWidth,bufferHeight,Bitmap.Config.ARGB_8888);
                ScreenBitmap.BitmapRectangle=new Rect(0,0,bufferWidth,bufferHeight);
            }
            ScreenBitmap.BitmapObj.setPixels(ScreenData,0,bufferWidth,0,0,bufferWidth,bufferHeight);
            Rect bitmapDestination=mIntegerZoom?new Rect(DestinationRectangle.left,DestinationRectangle.top,
                DestinationRectangle.left+mZoomedScreenWidth,DestinationRectangle.top+mZoomedScreenHeight):DestinationRectangle;
            if(mIntegerZoom && frameZoom==Zoom)canvas.drawBitmap(ScreenBitmap.BitmapObj,DestinationRectangle.left,DestinationRectangle.top,null);
            else canvas.drawBitmap(ScreenBitmap.BitmapObj,ScreenBitmap.BitmapRectangle,bitmapDestination,frameZoom==1?null:mDrawingPaint);

			if (sharpText != null && useSharpText() && !isScreenOff)
			{
				// Integer bitmap drawing uses its own height, which can differ from
				// the skin rectangle. Keep overlay and bitmap coordinates identical.
				Rect actual = mIntegerZoom ? new Rect(DestinationRectangle.left, DestinationRectangle.top,
					DestinationRectangle.left + mZoomedScreenWidth, DestinationRectangle.top + mZoomedScreenHeight) : DestinationRectangle;
				sharpText.draw(canvas, actual, mRawScreenWidth, mRawScreenHeight, mParentSkinBase.LCDPixelON, mParentSkinBase.LCDPixelOFF);
			}
            if(hdPlot!=null && useHDPlot() && !isScreenOff){
                Rect actual=mIntegerZoom?new Rect(DestinationRectangle.left,DestinationRectangle.top,DestinationRectangle.left+mZoomedScreenWidth,DestinationRectangle.top+mZoomedScreenHeight):DestinationRectangle;
                hdPlot.draw(canvas,actual,mParentSkinBase.LCDPixelON,mParentSkinBase.LCDPixelOFF);
            }
		}
	}

	public void ReleaseBitmaps()
	{
		if (ScreenBitmap != null && ScreenBitmap.BitmapObj != null)
		{
			ScreenBitmap.BitmapObj.recycle();
			ScreenBitmap.BitmapObj = null;
		}
	}
}

class ScaledBitmap
{
	public Bitmap	BitmapObj				= null;
	public Rect		BitmapRectangle			= null;
	public Rect		DestinationRectangle	= null;
}