# The ML Kit text-recognition plugin references every script's recognizer,
# but only the Japanese one is bundled (build.gradle.kts). Without these the
# release shrinker (R8) stops on the missing classes and no release APK can
# be built at all.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.korean.**

# AGP 9 runs R8 in full mode, which strips constructors that are only ever
# called by reflection. Seen in a release build on a device: the app crashed
# at launch because these could no longer be instantiated.
#
# ML Kit (text recognition, handwriting) registers its components through
# Firebase's ComponentDiscovery, which creates each registrar by name.
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
# Room creates each database's generated _Impl by name (WorkManager's
# WorkDatabase, used by plugins for background work).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
