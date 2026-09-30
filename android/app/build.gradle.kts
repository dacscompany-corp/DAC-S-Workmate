import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * The upload key, when this machine holds it. Kept in android/keystore.properties
 * (gitignored) pointing at a .jks OUTSIDE the repo: an upload key in git lets
 * anyone ship an update every installed phone accepts as genuine.
 * Absent is supported for debug builds and tests; a release refuses to build.
 */
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) FileInputStream(keystorePropertiesFile).use { load(it) }
}

android {
    namespace = "com.dacs.workmate"
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
        applicationId = "com.dacs.workmate"
        // Construction workers are on cheap, older phones -- same floor as DACS Attendance.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // From pubspec `version: name+code`. The code is ALSO a server gate
        // (0082): WorkMate must be >= 1000, every release must raise it.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "DAC'S WorkMate"
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Installs beside the real app, so a test build never replaces a worker's install.
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "WorkMate debug"
        }
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider, for handing the verified update APK to the system installer.
    implementation("androidx.core:core-ktx:1.13.1")
}

// A release signed with the wrong key (or none) can never update an installed
// WorkMate. Fail loudly instead of producing one.
gradle.taskGraph.whenReady {
    if (!keystorePropertiesFile.exists() && allTasks.any { it.name.contains("Release") }) {
        throw GradleException(
            "keystore.properties is missing: refusing to build a WorkMate release with no upload key. See README.md."
        )
    }
}
