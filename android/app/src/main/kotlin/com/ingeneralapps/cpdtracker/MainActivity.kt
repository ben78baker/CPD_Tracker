package com.ingeneralapps.cpdtracker

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cpd_tracker/migration_storage"
        ).setMethodCallHandler { call, result ->
            if (call.method != "availableBytes") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrEmpty()) {
                result.error("missing_path", "A destination path is required.", null)
                return@setMethodCallHandler
            }
            try {
                result.success(StatFs(path).availableBytes)
            } catch (_: IllegalArgumentException) {
                result.error("storage_unavailable", "Could not measure destination capacity.", null)
            }
        }
    }
}
