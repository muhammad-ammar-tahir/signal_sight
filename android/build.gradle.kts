allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
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

subprojects {
    pluginManager.withPlugin("com.android.library") {
        if (project.name == "arcore_flutter_plugin") {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val clazz = androidExt.javaClass
                    val method = clazz.getMethod("setNamespace", String::class.java)
                    method.invoke(androidExt, "com.difrancescogianmarco.arcore_flutter_plugin")
                } catch (e: Exception) {
                    println("Failed to set namespace for arcore_flutter_plugin: ${e.message}")
                }
            }
        }
    }
}
