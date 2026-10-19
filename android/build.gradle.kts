allprojects {
    repositories {
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
// Older plugins ship with a low compileSdk (flutter_pcm_sound pins 33). Some of
// their transitive AndroidX dependencies now require compiling against API 34+,
// which makes the release build fail the AAR metadata check. Raise every
// Android module to the SDK level the app itself uses.
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        val target = 36
        val methods = androidExtension.javaClass.methods
        val intSetter = methods.firstOrNull {
            it.name == "compileSdkVersion" &&
                it.parameterTypes.size == 1 &&
                (it.parameterTypes[0] == Int::class.javaPrimitiveType ||
                    it.parameterTypes[0] == Integer::class.java)
        }
        val propertySetter = methods.firstOrNull {
            it.name == "setCompileSdk" &&
                it.parameterTypes.size == 1 &&
                (it.parameterTypes[0] == Int::class.javaPrimitiveType ||
                    it.parameterTypes[0] == Integer::class.java)
        }
        (intSetter ?: propertySetter)?.invoke(androidExtension, target)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
