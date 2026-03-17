import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { stream ->
        keystoreProperties.load(stream)
    }
}
val hasReleaseSigning =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .all { key -> !keystoreProperties.getProperty(key).isNullOrBlank() }

fun readDartDefine(name: String): String? {
    val dartDefines = project.findProperty("dart-defines") as String? ?: return null
    return dartDefines
        .split(",")
        .asSequence()
        .mapNotNull { encoded ->
            runCatching {
                String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            }.getOrNull()
        }
        .mapNotNull { decoded ->
            val separatorIndex = decoded.indexOf('=')
            if (separatorIndex <= 0) {
                null
            } else {
                decoded.substring(0, separatorIndex) to decoded.substring(separatorIndex + 1)
            }
        }
        .firstOrNull { (key, _) -> key == name }
        ?.second
}

val defaultServerBaseUrl = "https://v0-fonex-backend-system-k6.vercel.app/api/v1/devices"
val serverBaseUrl = readDartDefine("SERVER_BASE_URL") ?: defaultServerBaseUrl
val escapedServerBaseUrl = serverBaseUrl
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")

android {
    namespace = "com.roycommunication.fonex"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.roycommunication.fonex"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
        buildConfigField("String", "SERVER_BASE_URL", "\"$escapedServerBaseUrl\"")
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    // EncryptedSharedPreferences for secure PIN storage
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}

flutter {
    source = "../.."
}
