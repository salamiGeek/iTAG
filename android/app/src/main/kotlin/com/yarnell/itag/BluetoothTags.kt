package com.yarnell.itag

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID

// Main-thread state owns the scanner and the one active GATT session.
@SuppressLint("MissingPermission")
internal class BluetoothTags(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val adapter get() = context.getSystemService(BluetoothManager::class.java)?.adapter
    private var scan: Scan? = null
    private var connection: Connection? = null

    fun startScan(result: Result) {
        stopScan()
        val scanner = adapter?.bluetoothLeScanner
        if (scanner == null) {
            result.error("bluetooth_off", "请开启手机蓝牙后重试。", null)
            return
        }
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handler.post {
                    val current = scan ?: return@post
                    if (current.callback !== this) return@post
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !result.isConnectable) {
                        return@post
                    }
                    emit(mapOf(
                        "type" to "found",
                        "id" to result.device.address,
                        "name" to (result.scanRecord?.deviceName?.takeIf { it.isNotBlank() } ?: "iTAG"),
                    ))
                }
            }

            override fun onScanFailed(errorCode: Int) {
                handler.post {
                    if (scan?.callback === this) {
                        endScan("蓝牙搜索失败，请稍后重试。")
                    }
                }
            }
        }
        val timeout = Runnable { endScan() }
        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(TAG_SERVICE)).build())
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scan = Scan(scanner, callback, timeout)
        try {
            scanner.startScan(filters, settings, callback)
            handler.postDelayed(timeout, 10_000L)
            result.success(null)
        } catch (failure: RuntimeException) {
            stopScan()
            result.error("scan_failed", "无法开始搜索，请检查蓝牙权限。", null)
        }
    }

    fun stopScan() {
        val active = scan ?: return
        scan = null
        handler.removeCallbacks(active.timeout)
        runCatching { active.scanner.stopScan(active.callback) }
    }

    private fun endScan(error: String? = null) {
        if (scan == null) return
        stopScan()
        emit(mapOf("type" to "scanEnded", "error" to error))
    }

    fun connect(id: String, automatic: Boolean, result: Result) {
        val bluetooth = adapter
        if (bluetooth == null || !bluetooth.isEnabled) {
            result.error("bluetooth_off", "请开启手机蓝牙后重试。", null)
            return
        }
        stopScan()
        disconnect()
        try {
            val device = bluetooth.getRemoteDevice(id)
            val gatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            if (gatt == null) {
                result.error("connect_failed", "无法开始连接，请重试。", null)
                return
            }
            val active = Connection(id, gatt, automatic, result)
            connection = active
            scheduleTimeout(active, 15_000L) {
                close(active, "connect_timeout", "连接超时。请让标签靠近手机，确认开机后重试。")
            }
        } catch (failure: RuntimeException) {
            result.error("connect_failed", "无法连接标签，请检查蓝牙后重试。", null)
        }
    }

    fun disconnect() {
        connection?.let { close(it, "disconnected", "标签连接已结束。") }
    }

    fun activityStopped() {
        endScan()
        val active = connection ?: return
        if (active.automatic && active.connectResult != null) {
            close(active, "background", null)
        }
    }

    @Suppress("DEPRECATION")
    fun sendAlert(level: Int, result: Result) {
        val active = connection
        val characteristic = active?.alert
        if (active == null || active.connectResult != null || characteristic == null) {
            result.error("not_ready", "请先连接支持响铃的标签。", null)
            return
        }
        if (active.writeResult != null) {
            result.error("busy", "上一条指令仍在发送。", null)
            return
        }
        val value = byteArrayOf(level.toByte())
        val writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        val accepted = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                active.gatt.writeCharacteristic(characteristic, value, writeType) ==
                    BluetoothStatusCodes.SUCCESS
            } else {
                characteristic.writeType = writeType
                characteristic.value = value
                active.gatt.writeCharacteristic(characteristic)
            }
        }.getOrDefault(false)
        if (!accepted) {
            result.error("write_failed", "指令发送失败，请重试。", null)
            return
        }
        active.writeResult = result
        scheduleTimeout(active, 4_000L) {
            close(active, "write_timeout", "指令发送超时，请重新连接标签。", reportLoss = true)
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            onActive(gatt) { active ->
                if (status != BluetoothGatt.GATT_SUCCESS ||
                    newState == BluetoothProfile.STATE_DISCONNECTED) {
                    close(active, "disconnected", "连接已断开。请确认标签开机后重试。", reportLoss = true)
                } else if (newState == BluetoothProfile.STATE_CONNECTED &&
                    !runCatching { gatt.discoverServices() }.getOrDefault(false)) {
                    close(active, "discovery_failed", "无法读取标签功能，请重新连接。")
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            onActive(gatt) { active ->
                when {
                    status != BluetoothGatt.GATT_SUCCESS ->
                        close(active, "discovery_failed", "无法读取标签功能，请重新连接。")
                    gatt.getService(TAG_SERVICE) == null ->
                        close(active, "unsupported", "这台设备没有 iTAG 服务。")
                    else -> {
                        active.alert = gatt.getService(ALERT_SERVICE)?.getCharacteristic(ALERT_LEVEL)
                            ?.takeIf { it.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0 }
                        val battery = gatt.getService(BATTERY_SERVICE)?.getCharacteristic(BATTERY_LEVEL)
                            ?.takeIf { it.properties and BluetoothGattCharacteristic.PROPERTY_READ != 0 }
                        if (battery == null ||
                            !runCatching { gatt.readCharacteristic(battery) }.getOrDefault(false)) {
                            ready(active, null)
                        }
                    }
                }
            }
        }

        @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            handleRead(gatt, characteristic.uuid, characteristic.value?.copyOf(), status)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            handleRead(gatt, characteristic.uuid, value.copyOf(), status)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            onActive(gatt) { active ->
                if (characteristic.uuid != ALERT_LEVEL) return@onActive
                val result = active.writeResult ?: return@onActive
                active.writeResult = null
                clearTimeout(active)
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    Log.d(LOG_TAG, "Alert write completed")
                    result.success(null)
                } else {
                    result.error("write_failed", "指令发送失败，请重试。", null)
                }
            }
        }
    }

    private fun handleRead(gatt: BluetoothGatt, uuid: UUID, value: ByteArray?, status: Int) {
        onActive(gatt) { active ->
            if (uuid != BATTERY_LEVEL || active.connectResult == null) return@onActive
            val battery = if (status == BluetoothGatt.GATT_SUCCESS) {
                value?.singleOrNull()?.toUByte()?.toInt()?.takeIf { it in 0..100 }
            } else null
            ready(active, battery)
        }
    }

    private fun onActive(gatt: BluetoothGatt, run: (Connection) -> Unit) {
        handler.post {
            val active = connection ?: return@post
            if (active.gatt === gatt) run(active)
        }
    }

    private fun ready(active: Connection, battery: Int?) {
        val result = active.connectResult ?: return
        active.connectResult = null
        clearTimeout(active)
        Log.d(LOG_TAG, "Tag ready, battery=$battery, canRing=${active.alert != null}")
        result.success(mapOf("battery" to battery, "canRing" to (active.alert != null)))
    }

    private fun scheduleTimeout(active: Connection, delay: Long, action: () -> Unit) {
        clearTimeout(active)
        active.timeout = Runnable { if (connection === active) action() }
            .also { handler.postDelayed(it, delay) }
    }

    private fun clearTimeout(active: Connection) {
        active.timeout?.let(handler::removeCallbacks)
        active.timeout = null
    }

    private fun close(
        active: Connection,
        code: String,
        message: String?,
        reportLoss: Boolean = false,
    ) {
        connection = null
        clearTimeout(active)
        runCatching { active.gatt.disconnect() }
        runCatching { active.gatt.close() }
        active.connectResult?.error(code, message, null)
        active.writeResult?.error(code, message, null)
        if (reportLoss && active.connectResult == null) {
            emit(mapOf("type" to "disconnected", "id" to active.id))
        }
    }

    private data class Scan(
        val scanner: BluetoothLeScanner,
        val callback: ScanCallback,
        val timeout: Runnable,
    )

    private class Connection(
        val id: String,
        val gatt: BluetoothGatt,
        val automatic: Boolean,
        var connectResult: Result?,
        var alert: BluetoothGattCharacteristic? = null,
        var writeResult: Result? = null,
        var timeout: Runnable? = null,
    )

    private companion object {
        const val LOG_TAG = "iTAG.BLE"
        fun uuid(short: String): UUID = UUID.fromString("0000$short-0000-1000-8000-00805f9b34fb")
        val TAG_SERVICE = uuid("ffe0")
        val ALERT_SERVICE = uuid("1802")
        val ALERT_LEVEL = uuid("2a06")
        val BATTERY_SERVICE = uuid("180f")
        val BATTERY_LEVEL = uuid("2a19")
    }
}
