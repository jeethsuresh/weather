package dev.jeeth.local_weather

import android.content.Intent
import android.net.Uri
import cool.gravitas.navigation.GravitasFlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : GravitasFlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.jeeth.daybreak/actions")
            .setMethodCallHandler { call, result ->
                if (call.method == "timeZone") {
                    result.success(java.util.TimeZone.getDefault().id)
                } else if (call.method != "openLink") {
                    result.notImplemented()
                } else {
                    val uri = Uri.parse(call.argument<String>("url") ?: "")
                    if (uri.scheme != "https") {
                        result.error("invalid_url", "Only HTTPS links can be opened", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("unavailable", "No browser available", null)
                        }
                    }
                }
            }
    }
}
