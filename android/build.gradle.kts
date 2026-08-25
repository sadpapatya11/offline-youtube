allprojects {
    repositories {
        // FIX(tedarik-zinciri): jitpack.io kaldırıldı. Hiçbir bağımlılık oradan
        // gelmiyordu (tümü google() ve mavenCentral() ile çözülüyor) ama grup
        // filtresi olmadığı için HER koordinat orada da aranıyordu: jitpack
        // rastgele bir GitHub deposunu istek üzerine derleyip yayımladığından,
        // beklenen group/artifact adını kapan bir saldırgan APK'ya kod
        // sokabilirdi. Gerekirse content filtresiyle geri eklenir:
        // maven(url = "https://jitpack.io") { content { includeGroupByRegex("com\\.github\\..*") } }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.projectDirectory.dir("../build")
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
