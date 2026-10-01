#ifndef ANDROID_LOG
#define ANDROID_LOG
	#ifdef __APPLE__
    #include <stdio.h>
    #define ANDROID_LOG_DEBUG 3
    #define ANDROID_LOG_INFO 4
    #define ANDROID_LOG_WARN 5
    #define ANDROID_LOG_ERROR 6
    #define ANDROID_LOG_FATAL 7
    #define __android_log_print(level, tag, ...) ((void)0)
    #else
    #include <android/log.h>
    #endif

	#define DEBUG_NAME "Graph89"

	#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG , DEBUG_NAME, __VA_ARGS__)
	#define LOGI(...) __android_log_print(ANDROID_LOG_INFO , DEBUG_NAME, __VA_ARGS__)
	#define LOGW(...) __android_log_print(ANDROID_LOG_WARN , DEBUG_NAME, __VA_ARGS__)
	#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR , DEBUG_NAME, __VA_ARGS__)
	#define LOGF(...) __android_log_print(ANDROID_LOG_FATAL , DEBUG_NAME, __VA_ARGS__)

#endif
