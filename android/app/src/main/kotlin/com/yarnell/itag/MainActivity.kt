package com.yarnell.itag

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null
    private val bluetooth = BluetoothTags(this) { event -> eventSink?.success(event) }
    private var permissionRequest: PermissionRequest? = null
    private var active = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val preferences = getSharedPreferences("itag", MODE_PRIVATE)
        EventChannel(messenger, "itag/tag_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        MethodChannel(messenger, "itag/tags").setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> result.success(preferences.getString("library", null))
                "save" -> {
                    val library = call.arguments as String
                    if (preferences.edit().putString("library", library).commit()) {
                        result.success(null)
                    } else {
                        result.error("storage", null, null)
                    }
                }
                "startScan" -> withBluetooth(result, scan = true) { bluetooth.startScan(result) }
                "stopScan" -> {
                    permissionRequest?.takeIf { it.scan }?.let {
                        it.cancelled = true
                    }
                    bluetooth.stopScan()
                    result.success(null)
                }
                "connect" -> {
                    val id = call.argument<String>("id")!!
                    val automatic = call.argument<Boolean>("automatic") == true
                    if (automatic && !active) {
                        result.error("background", null, null)
                    } else {
                        withBluetooth(result, automatic = automatic) {
                            bluetooth.connect(id, automatic, result)
                        }
                    }
                }
                "disconnect" -> {
                    bluetooth.disconnect()
                    result.success(null)
                }
                "sendAlert" -> withBluetooth(result) {
                    bluetooth.sendAlert(call.arguments as Int, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        active = true
        super.onStart()
    }

    override fun onStop() {
        active = false
        bluetooth.activityStopped()
        super.onStop()
    }

    override fun onDestroy() {
        bluetooth.stopScan()
        bluetooth.disconnect()
        super.onDestroy()
    }

    private fun withBluetooth(
        result: MethodChannel.Result,
        scan: Boolean = false,
        automatic: Boolean = false,
        action: () -> Unit,
    ) {
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (scan) arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            else arrayOf(Manifest.permission.BLUETOOTH_CONNECT)
        } else if (scan) {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        } else {
            emptyArray()
        }
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        when {
            missing.isEmpty() -> action()
            automatic -> result.error("permission", "请手动连接并允许蓝牙权限。", null)
            permissionRequest != null -> result.error("permission_busy", "请先完成系统权限设置。", null)
            else -> {
                permissionRequest = PermissionRequest(result, scan, action)
                requestPermissions(missing.toTypedArray(), BLUETOOTH_REQUEST)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != BLUETOOTH_REQUEST) return
        val pending = permissionRequest ?: return
        permissionRequest = null
        when {
            pending.cancelled -> pending.result.success(null)
            grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED } ->
                pending.action()
            else -> {
                val message = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    "请在系统设置中允许「附近的设备」权限后重试。"
                } else {
                    "此 Android 版本搜索蓝牙需要位置权限，请在系统设置中开启后重试。"
                }
                pending.result.error("permission", message, null)
            }
        }
    }

    private data class PermissionRequest(
        val result: MethodChannel.Result,
        val scan: Boolean,
        val action: () -> Unit,
        var cancelled: Boolean = false,
    )

    private companion object {
        const val BLUETOOTH_REQUEST = 142
    }
}
