# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# Calculator settings are serialized by Gson using field names and generic types.
-keepattributes Signature
-keep class com.graph89.common.CalculatorInstance { *; }
-keep class com.graph89.common.CalculatorConfiguration { *; }

# TiEmu looks up this callback by its literal class and method names in JNI.
-keep class com.graph89.emulationcore.TIEmuThread {
    public static void ReceiveFile(java.lang.String, java.lang.String);
}
