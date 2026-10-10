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


#include <jni.h>
#include <wrappercommon.h>
#include <tiemuwrapper.h>
#include <androidlog.h>
#include <ti68k_def.h>
#include <string.h>
#include "hdtext.h"

extern JNIEnv * DbusJNIenv;
JNIEXPORT void JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuStep1LoadDefaultConfig(JNIEnv * env, jobject obj)
{
	tiemu_step1_load_defaultconfig();
	LOGI("TiEmu LoadDefaultConfig");
}

JNIEXPORT jint JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuStep2LoadImage(JNIEnv * env, jobject obj, jstring image_file)
{
	const char * filename = (*env)->GetStringUTFChars(env, image_file, 0);
	int code = tiemu_step2_load_image(filename);
	(*env)->ReleaseStringUTFChars(env, image_file, filename);
	LOGI("TiEmu LoadImage %d", code);
	return (jint)code;
}

JNIEXPORT jint JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuStep3Init(JNIEnv * env, jobject obj)
{
	int code = tiemu_step3_init();
	LOGI("TiEmu Init %d", code);
	return (jint)code;
}

JNIEXPORT jint JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuStep4Reset (JNIEnv * env, jobject obj)
{
	int code = tiemu_step4_reset();
	LOGI("TiEmu Reset %d", code);
	return (jint)code;
}

JNIEXPORT jint JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuSaveState(JNIEnv * env, jobject obj, jstring state_file)
{
	const char* filename = (*env)->GetStringUTFChars(env, state_file, 0);
	int code = tiemu_save_state(filename);
	(*env)->ReleaseStringUTFChars(env, state_file, filename);
	LOGI("SaveState %d", code);
	return (jint)code;
}

JNIEXPORT void JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuTurnScreenOn(JNIEnv * env, jobject obj)
{
	tiemu_turn_screen_ON();
	LOGI("TiEmu Turn Screen ON");
}

JNIEXPORT void JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuPatch(JNIEnv * env, jobject obj, jstring num, jstring vernum)
{
	const char * serial = (*env)->GetStringUTFChars(env, num, 0);
	const char * ver = (*env)->GetStringUTFChars(env, vernum, 0);

	tiemu_patch(serial, ver);

	(*env)->ReleaseStringUTFChars(env, num, serial);
	(*env)->ReleaseStringUTFChars(env, vernum, ver);
}

JNIEXPORT jint JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuUploadFile(JNIEnv * env, jobject obj, jstring str)
{
	const char * filename = (*env)->GetStringUTFChars(env, str, 0);
	int code = tiemu_upload_file(filename);
	(*env)->ReleaseStringUTFChars(env, str, filename);

	LOGI("TiEmu Upload File");
	return (jint)code;
}

JNIEXPORT jint JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuLoadState(JNIEnv * env, jobject obj, jstring str)
{
	const char * filename = (*env)->GetStringUTFChars(env, str, 0);

	int code = tiemu_load_state(filename);

	(*env)->ReleaseStringUTFChars(env, str, filename);
	LOGI("TiEmu LoadState %d", code);

	return (jint)code;
}

JNIEXPORT void JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuSyncClock(JNIEnv * env, jobject obj)
{
	tiemu_sync_clock();
}

JNIEXPORT void JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuRunEngine(JNIEnv * env, jobject obj)
{
	DbusJNIenv = env;
	tiemu_run_engine();
}

JNIEXPORT void JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuRunTurboChunk(JNIEnv *env, jobject obj)
{
    DbusJNIenv = env;
    tiemu_run_turbo_chunk();
}

JNIEXPORT jboolean JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuIsBusy(JNIEnv *env, jobject obj)
{
    return tiemu_is_busy() ? JNI_TRUE : JNI_FALSE;
}

/* Read the ROM's three standard font attributes. No ROM data is bundled in the
 * app, and no emulated registers, memory, or instructions are modified.
 * Null means not loaded yet; empty templates mean an unsupported layout. */
static unsigned int font_be32(const unsigned char *p)
{
    return ((unsigned int)p[0] << 24) | ((unsigned int)p[1] << 16)
        | ((unsigned int)p[2] << 8) | p[3];
}

JNIEXPORT jbyteArray JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuGetFontTemplates(JNIEnv *env, jobject obj)
{
    unsigned int pos, offsets[3];
    unsigned char result[3 * 256 * 12];
    int f, c, row;
    if (!tihw.rom) return NULL;
    if ((tihw.calc_type != TI89 && tihw.calc_type != TI89t)
        || tihw.rom_size < 2560) return (*env)->NewByteArray(env, 0);
    for (pos = 0; pos + 24 <= (unsigned int)tihw.rom_size; pos += 2)
    {
        const unsigned char *p = tihw.rom + pos;
        if (font_be32(p) != 0x300 || font_be32(p + 8) != 0x301
            || font_be32(p + 16) != 0x302) continue;
        for (f = 0; f < 3; ++f)
        {
            unsigned int address = font_be32(p + f * 8 + 4);
            int stride = f == 0 ? 6 : (f == 1 ? 8 : 10);
            if (address < tihw.rom_base) break;
            offsets[f] = address - tihw.rom_base;
            if (offsets[f] > (unsigned int)tihw.rom_size - 256 * stride) break;
            /* Validate printable characters and the space before trusting a table. */
            for (c = 32; c < 127; ++c)
            {
                const unsigned char *g = tihw.rom + offsets[f] + c * stride;
                if (f == 0 && (g[0] < 1 || g[0] > 8)) break;
                if (c == 32)
                    for (row = (f == 0); row < stride; ++row)
                        if (g[row]) break;
                if (c == 32 && row < stride) break;
            }
            if (c != 127) break;
        }
        if (f != 3) continue;
        memset(result, 0, sizeof(result));
        for (f = 0; f < 3; ++f)
            for (c = 0; c < 256; ++c)
            {
                int stride = f == 0 ? 6 : (f == 1 ? 8 : 10);
                const unsigned char *g = tihw.rom + offsets[f] + c * stride;
                unsigned char *out = result + (f * 256 + c) * 12;
                out[0] = f == 0 ? g[0] : (f == 1 ? 6 : 8);
                out[1] = f == 0 ? 5 : stride;
                for (row = 0; row < out[1]; ++row)
                    out[2 + row] = f == 2 ? g[row] : g[row + (f == 0)] << 1;
            }
        jbyteArray array = (*env)->NewByteArray(env, sizeof(result));
        if (array) (*env)->SetByteArrayRegion(env, array, 0, sizeof(result), (jbyte *)result);
        return array;
    }
    return (*env)->NewByteArray(env, 0);
}

JNIEXPORT void JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuRetainedTextEnable(JNIEnv *env,jobject obj,jboolean enabled)
{
    hdtext_enable(enabled);
}
JNIEXPORT jintArray JNICALL Java_com_graph89_emulationcore_EmulatorActivity_nativeTiEmuGetRetainedText(JNIEnv *env,jobject obj,jbooleanArray pixels)
{
    if(!pixels || (*env)->GetArrayLength(env,pixels)!=16000)return (*env)->NewIntArray(env,0);
    jboolean *p=(*env)->GetBooleanArrayElements(env,pixels,NULL);
    if(!p)return NULL;
    int32_t packets[1024*12];
    int count=tiemu_copy_retained_screen((const uint8_t *)p,packets);
    (*env)->ReleaseBooleanArrayElements(env,pixels,p,JNI_ABORT);
    jintArray result=(*env)->NewIntArray(env,count*12);
    if(result)(*env)->SetIntArrayRegion(env,result,0,count*12,(const jint *)packets);
    return result;
}
