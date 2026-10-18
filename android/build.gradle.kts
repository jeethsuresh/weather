allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // home_widget 0.8 uses dynamic AndroidX ranges. Keep its transitive Android
    // libraries stable and compatible with this project's API 36 toolchain.
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            when (requested.group) {
                "androidx.glance" -> useVersion("1.1.1")
                "androidx.work" -> useVersion("2.10.1")
                "org.jetbrains.kotlinx" -> if (requested.name.startsWith("kotlinx-coroutines")) useVersion("1.9.0")
            }
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
