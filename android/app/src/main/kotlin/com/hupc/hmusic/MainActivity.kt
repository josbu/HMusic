package com.hupc.hmusic

import android.content.Context
import android.webkit.CookieManager
import androidx.core.view.WindowCompat
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return AudioServicePlugin.getFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hmusic/cookies")
            .setMethodCallHandler { call, result ->
                if (call.method == "getCookies") {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("ARG_ERROR", "url is required", null)
                        return@setMethodCallHandler
                    }
                    val cookie = CookieManager.getInstance().getCookie(url) ?: ""
                    result.success(cookie)
                } else {
                    result.notImplemented()
                }
            }
    }
}
