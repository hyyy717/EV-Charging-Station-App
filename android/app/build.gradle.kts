plugins {
    id("com.android.application")
    id("kotlin-android")
    // Áp dụng plugin google-services vào module app
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied last.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.tram_sac"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.tram_sac"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
