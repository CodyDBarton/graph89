#ndk-build NDK_DEBUG=1
APP_CFLAGS += -Wno-error=format-security -std=gnu99 -fcommon -fno-strict-aliasing
APP_PLATFORM := android-21
APP_MODULES := glib-2.0 ticables2-1.3.3 ticonv-1.1.3 tifiles2-1.1.5 ticalcs2-1.1.7 tiemu-3.03 tilem-2.0 wrapper
