allprojects {
    repositories {
        google()
        mavenCentral()
    }
    configurations.all {
        exclude(group = "com.android.support")
        resolutionStrategy {
            force("androidx.vectordrawable:vectordrawable:1.1.0")
            force("androidx.vectordrawable:vectordrawable-animated:1.1.0")
            force("androidx.core:core:1.13.1")
            force("androidx.appcompat:appcompat:1.6.1")
        }
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
    val subproject = this
    subproject.plugins.withId("com.android.library") {
        val android = subproject.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (android != null) {
            android.compileSdk = 34
            if (android.namespace == null && subproject.name != "app") {
                android.namespace = if (subproject.group.toString().isNotEmpty()) {
                    subproject.group.toString()
                } else {
                    "com.belekapos.${subproject.name.replace("-", "_")}"
                }
            }
        }
    }
}

subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android")
            if (android is com.android.build.gradle.BaseExtension) {
                android.compileSdkVersion(34)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val targetVer = project.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
            ?.compileOptions
            ?.targetCompatibility

        compilerOptions {
            when (targetVer) {
                JavaVersion.VERSION_17 -> jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                JavaVersion.VERSION_11 -> jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
                JavaVersion.VERSION_21 -> jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
                else -> jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
