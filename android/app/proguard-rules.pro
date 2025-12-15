# Ignore warnings about optional ML Kit language packages
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep generic ML Kit classes
-keep class com.google.mlkit.vision.text.** { *; }