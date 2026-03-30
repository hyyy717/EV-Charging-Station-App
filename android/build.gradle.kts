allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
plugins {
    id("com.android.application") version "8.9.1" apply false
    // Sử dụng phiên bản Kotlin từ log lỗi của bạn
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false

    // Khai báo plugin google-services
    id("com.google.gms.google-services") version "4.4.1" apply false
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
