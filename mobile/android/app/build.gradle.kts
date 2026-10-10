plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hanko.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications: it uses java.time APIs that
        // don't exist on older Android versions, and desugaring backports them.
        // Without this the build fails outright at :app:checkDebugAarMetadata.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hanko.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Phones are ARM. The Flutter plugin packages all three ABIs whatever
        // the build targets, and the plugins' native code (ML Kit OCR + digital
        // ink, ~20 MB per ABI) rides along, so the release APK carried a whole
        // x86_64 copy only emulators and Chromebooks can run. Keep the ARM ABIs
        // this build targets (`flutter run` on a phone passes just its own); an
        // x86_64-only build (`flutter run` on an emulator) keeps x86_64.
        if (!project.hasProperty("split-per-abi")) {
            val flutterAbis = mapOf(
                "android-arm" to "armeabi-v7a",
                "android-arm64" to "arm64-v8a",
                "android-x64" to "x86_64",
            )
            val targetAbis = (project.findProperty("target-platform") as String?
                ?: "android-arm,android-arm64,android-x64")
                .split(",").mapNotNull { flutterAbis[it.trim()] }
            val armAbis = targetAbis.filter { it != "x86_64" }.ifEmpty { targetAbis }
            ndk {
                abiFilters.clear()
                abiFilters += armAbis
            }
        }
    }

    // Store native libraries compressed: about 40% of their size in the APK,
    // which is what people download. They are unpacked once at install.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // Japanese script model for camera capture (bundled, works offline); the
    // ML Kit plugin only declares it compileOnly.
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
}

flutter {
    source = "../.."
}
