import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "ar.dusan.bitacora"
    compileSdk = 35

    defaultConfig {
        // El mismo identificador que la app de iPhone.
        applicationId = "ar.dusan.bitacora"
        // Android 12: desde ahí existe el reconocimiento de voz que corre en el
        // teléfono (`createOnDeviceSpeechRecognizer`). Sin eso no hay manera de
        // dictar sin mandar el audio afuera, que es la regla 1.
        minSdk = 31
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"

        // El servidor dentro de la app (06/10/2026), para la APK de un cliente:
        // `servidor.properties` (al lado de este proyecto, y que git ignora)
        // trae `url` y `token`. Sin ese archivo quedan vacíos y la app hace lo
        // de siempre: la dirección y el token se cargan en Ajustes.
        val servidor = Properties().apply {
            rootProject.file("servidor.properties").takeIf { it.exists() }?.reader()?.use { load(it) }
        }
        buildConfigField("String", "SERVIDOR_URL", "\"${servidor.getProperty("url", "")}\"")
        buildConfigField("String", "SERVIDOR_TOKEN", "\"${servidor.getProperty("token", "")}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.kotlinx.coroutines.test)
}
