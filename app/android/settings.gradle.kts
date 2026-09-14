pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // Los espejos PRIMERO, y no es una preferencia: desde aquí los repositorios de
        // Google devuelven 404 en los artefactos que sí existen. Comprobado el 14/09/2026
        // con el propio plugin de Android 9.1.0 — `dl.google.com/dl/android/maven2/…`
        // contesta 404 y `maven.aliyun.com/repository/google/…` contesta 200 con el mismo
        // fichero. Sin esto la compilación del APK no arranca.
        //
        // `google()` y `mavenCentral()` se dejan DETRÁS a propósito: si un día el espejo
        // se queda corto o desaparece, Gradle sigue por ahí en vez de fallar.
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
