import java.util.Properties
import java.io.FileInputStream
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.twopick.picandtrip"
    compileSdk = flutter.compileSdkVersion
    // NDK 버전 설정을 주석 처리
    // ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
    
    // 릴리즈 키 서명 설정 추가 - 안전한 방식으로 수정
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("keystore.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        println("🔑 Keystore properties loaded successfully")
    } else {
        println("⚠️ keystore.properties file not found - using debug signing")
    }
    
    signingConfigs {
        create("release") {
            // keystore.properties 파일이 있을 때만 서명 설정 적용
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
                
                // 안전한 로깅
                val storeFilePath = keystoreProperties["storeFile"]
                if (storeFilePath != null) {
                    println("🔑 Keystore file path: ${file(storeFilePath).absolutePath}")
                }
            } else {
                // 디버그 서명 사용
                keyAlias = "androiddebugkey"
                keyPassword = "android"
                storeFile = file("${System.getProperty("user.home")}/.android/debug.keystore")
                storePassword = "android"
                println("🔑 Using debug keystore for release build")
            }
        }
    }
    
    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.twopick.picandtrip"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 릴리즈 키 사용으로 변경
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false 
            isShrinkResources = false // 명시적으로 false로 추가!

            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
