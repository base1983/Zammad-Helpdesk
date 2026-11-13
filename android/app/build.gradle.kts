import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Everything secret or account-specific comes from files that are NOT in git:
//   local.properties        AdMob ids (admob.*)
//   keystore.properties     release signing (storeFile, storePassword, keyAlias, keyPassword)
//   app/google-services.json  Firebase (push); without it the app builds with push disabled
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val keystoreProps = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasFirebase = file("google-services.json").exists()

// Google's public sample ids: always safe, never earn money.
val testAdMobAppId = "ca-app-pub-3940256099942544~3347511713"
val testBanner = "ca-app-pub-3940256099942544/9214589741"
val testInterstitial = "ca-app-pub-3940256099942544/1033173712"
val testAppOpen = "ca-app-pub-3940256099942544/9257395921"

android {
    namespace = "com.baseonline.zammadmobile"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.baseonline.zammadmobile"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "1.2.1"
        androidResources.localeFilters += listOf("en", "nl", "de", "fr")
        buildConfigField("boolean", "HAS_FIREBASE", hasFirebase.toString())
    }

    signingConfigs {
        if (keystoreProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["admobAppId"] = testAdMobAppId
            buildConfigField("String", "AD_BANNER", "\"$testBanner\"")
            buildConfigField("String", "AD_INTERSTITIAL", "\"$testInterstitial\"")
            buildConfigField("String", "AD_APP_OPEN", "\"$testAppOpen\"")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
            // Falls back to the test ids until the real ones are in local.properties,
            // so a release build without them still works but shows test ads.
            manifestPlaceholders["admobAppId"] = localProps.getProperty("admob.appId", testAdMobAppId)
            buildConfigField("String", "AD_BANNER", "\"${localProps.getProperty("admob.banner", testBanner)}\"")
            buildConfigField("String", "AD_INTERSTITIAL", "\"${localProps.getProperty("admob.interstitial", testInterstitial)}\"")
            buildConfigField("String", "AD_APP_OPEN", "\"${localProps.getProperty("admob.appOpen", testAppOpen)}\"")
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
    packaging {
        resources.excludes += setOf("META-INF/versions/9/OSGI-INF/MANIFEST.MF", "META-INF/{AL2.0,LGPL2.1}")
    }
    testOptions.unitTests.isReturnDefaultValues = true
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.biometric)
    implementation(libs.androidx.work)
    implementation(libs.androidx.browser)
    implementation(libs.androidx.splashscreen)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)

    implementation(libs.coroutines.android)
    implementation(libs.coroutines.play.services)
    implementation(libs.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.coil.compose)
    implementation(libs.bouncycastle)
    implementation(libs.lottie.compose)

    implementation(libs.billing.ktx)
    implementation(libs.play.ads)
    implementation(libs.ump)
    implementation(libs.play.review)
    implementation(libs.play.wearable)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    testImplementation(libs.junit)
}

// Firebase is optional at build time: the plugin needs google-services.json,
// which is deliberately not in this (public) repository.
if (hasFirebase) {
    apply(plugin = libs.plugins.google.services.get().pluginId)
}
