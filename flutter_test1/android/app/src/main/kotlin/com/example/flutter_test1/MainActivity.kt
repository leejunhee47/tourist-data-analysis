package com.example.flutter_test1  // 실제 패키지명으로

import android.os.Bundle
import android.util.Base64
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import java.security.MessageDigest
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    // 아래부터 추가
    try {
      val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
      info.signatures?.forEach { sig ->
        val md = MessageDigest.getInstance("SHA")
        md.update(sig.toByteArray())
        Log.i("KeyHash", Base64.encodeToString(md.digest(), Base64.DEFAULT))
    }
    } catch (e: Exception) {
      Log.e("KeyHash", "Hash 계산 실패", e)
    }
    // 여기까지
  }
}
