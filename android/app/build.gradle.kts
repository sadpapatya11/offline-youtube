plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

// FIX(security): Keystore repo'da tutulmaz — keystore.properties gitignore'da.
// Dosya yoksa release imzası devre dışı kalır (debug anahtarı kullanılır),
// böylece keystore'suz ortamlarda build bozulmaz.
fun loadKeystoreProps(project: org.gradle.api.Project): Properties? {
    val propsFile = project.file("keystore.properties")
    if (!propsFile.exists()) {
        project.logger.warn("keystore.properties bulunamadı — release imzası devre dışı, debug anahtarı kullanılacak.")
        return null
    }
    val props = Properties()
    propsFile.inputStream().use { props.load(it) }
    val storeFile = project.file(props.getProperty("storeFile"))
    if (!storeFile.exists()) {
        project.logger.warn("Keystore dosyası yok (${storeFile.absolutePath}) — release imzası devre dışı.")
        return null
    }
    return props
}

android {
    namespace = "com.offlineyoutube.offlineyoutube"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.offlineyoutube.offlineyoutube"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64"))
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // FIX(security): Release APK artık herkese açık debug anahtarıyla
            // imzalanmıyor. Keystore/şifreler android/app/keystore.properties
            // dosyasında tutulur (gitignore'da) ve üretim dışındaki ortamlarda
            // imzalama devre dışı kalır (geliştirici imzası kullanılır).
            val releaseProps = loadKeystoreProps(project)
            signingConfig = if (releaseProps != null) {
                signingConfigs.create("release") {
                    storeFile = project.file(releaseProps.getProperty("storeFile"))
                    storePassword = releaseProps.getProperty("storePassword")
                    keyAlias = releaseProps.getProperty("keyAlias")
                    keyPassword = releaseProps.getProperty("keyPassword")
                }
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            // FIX(proguard): youtubedl-android keep kuralları hazır — minify
            // açılırsa indirmelerin bozulmaması için bkz. proguard-rules.pro
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:aria2c:0.18.1")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}

flutter {
    source = "../.."
}
