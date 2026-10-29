import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val damaSigning = Properties()
val damaSigningFile = rootProject.file("key.properties")
if (damaSigningFile.exists()) {
    damaSigningFile.inputStream().use { damaSigning.load(it) }
}

android {
    namespace = "dev.ibrahimeng.dama_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "dev.ibrahimeng.dama_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (damaSigningFile.exists()) {
            create("damaRelease") {
                keyAlias = damaSigning.getProperty("keyAlias")
                keyPassword = damaSigning.getProperty("keyPassword")
                storeFile = file(damaSigning.getProperty("storeFile"))
                storePassword = damaSigning.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Personal APK preview works immediately. Supply an ignored
            // android/key.properties file for a stable distribution signature.
            signingConfig = signingConfigs.getByName(
                if (damaSigningFile.exists()) "damaRelease" else "debug"
            )
        }
    }
}

flutter {
    source = "../.."
}
