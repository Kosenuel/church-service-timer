import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "org.kosenuel.cuekeeper"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "io.github.immanuelokose.churchservicetimer"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    // Release signing comes from android/key.properties (local builds) or the
    // CST_KEYSTORE_* environment variables (CI). Without either, the release
    // build falls back to the debug key so local prototype builds still work.
    val keyProperties = Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }
    fun signingValue(property: String, env: String): String? =
        keyProperties.getProperty(property) ?: System.getenv(env)
    val releaseStore = signingValue("storeFile", "CST_KEYSTORE_PATH")
    signingConfigs {
        if (releaseStore != null) {
            create("release") {
                storeFile = file(releaseStore)
                storePassword = signingValue("storePassword", "CST_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "CST_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "CST_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }
