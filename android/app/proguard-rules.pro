# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep application class
-keep class io.truyencv.app.** { *; }

# Riverpod / Dart reflection
-keep class * extends java.lang.annotation.Annotation { *; }

# Gson / JSON (nếu dùng)
-keepattributes Signature
-keepattributes *Annotation*

# OkHttp / Dio
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# Keep native methods
-keepclassmembers class * {
    native <methods>;
}

# Missing classes detected by R8 (auto-generated)
-dontwarn javax.lang.model.element.Modifier
