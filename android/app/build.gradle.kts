plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.omniconnect.omni_connect_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.omniconnect.omni_connect_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // We only need the 64-bit ABIs that modern phones ship with. Dropping
        // 32-bit halves the build time and the APK size of the embedded runtime.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                // llama.cpp is C++17 and uses the NDK's shared STL.
                arguments += listOf("-DANDROID_STL=c++_shared")
                cppFlags += listOf("-O3", "-fexceptions", "-frtti")
            }
        }
    }

    // Builds OmniConnect's embedded llama.cpp runtime (libomni_llama.so) straight
    // into the APK. The shim sources are shared with the desktop build so there
    // is exactly one place where llama.cpp's ABI is described.
    externalNativeBuild {
        cmake {
            path = file("../../../Desktop-Application/native/omni_llama/CMakeLists.txt")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
