allprojects {
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
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
