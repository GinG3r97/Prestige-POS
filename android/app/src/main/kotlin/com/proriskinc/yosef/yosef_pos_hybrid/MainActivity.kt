package com.proriskinc.yosef.yosef_pos_hybrid

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Dart to the Android-12+ runtime Bluetooth permissions
 * (BLUETOOTH_CONNECT / BLUETOOTH_SCAN). The print_bluetooth_thermal plugin
 * *checks* these but never *requests* them, so on a fresh Android 12+ tablet
 * the paired-printer list comes back empty until the app prompts. iOS is
 * untouched — there the plugin's BLE access triggers the system prompt via the
 * Info.plist usage string.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "prestige.pos/bt_permissions"
    private val requestCode = 4201
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensure" -> ensureBtPermissions(result)
                    else -> result.notImplemented()
                }
            }
    }

    /** Runtime BT permissions only exist on Android 12 (API 31, S) and up. */
    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_SCAN,
            )
        } else {
            emptyArray()
        }

    private fun allGranted(perms: Array<String>): Boolean =
        perms.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

    private fun ensureBtPermissions(result: MethodChannel.Result) {
        val perms = requiredPermissions()
        if (perms.isEmpty() || allGranted(perms)) {
            result.success(true)
            return
        }
        if (pendingResult != null) {
            // A prompt is already in flight — don't stack dialogs.
            result.success(false)
            return
        }
        pendingResult = result
        ActivityCompat.requestPermissions(this, perms, requestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == this.requestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingResult?.success(granted)
            pendingResult = null
        }
    }
}
