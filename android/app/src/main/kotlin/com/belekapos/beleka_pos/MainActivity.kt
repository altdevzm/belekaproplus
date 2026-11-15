package com.belekapos.beleka_pos

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val BT_CHANNEL = "com.belekapos.beleka_pos/bluetooth"
        private const val REQ_BLUETOOTH_PERMS = 9042
    }

    private var pendingPermResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermissions" -> handleRequestBluetoothPermissions(result)
                    "getBondedDevices" -> handleGetBondedDevices(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requiredBluetoothPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun hasAllBluetoothPermissions(): Boolean {
        return requiredBluetoothPermissions().all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun handleRequestBluetoothPermissions(result: MethodChannel.Result) {
        if (hasAllBluetoothPermissions()) {
            result.success(true)
            return
        }
        pendingPermResult?.success(false)
        pendingPermResult = result
        ActivityCompat.requestPermissions(this, requiredBluetoothPermissions(), REQ_BLUETOOTH_PERMS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_BLUETOOTH_PERMS) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermResult?.success(granted)
            pendingPermResult = null
        }
    }

    private fun handleGetBondedDevices(result: MethodChannel.Result) {
        if (!hasAllBluetoothPermissions()) {
            result.success(emptyList<Map<String, String>>())
            return
        }
        try {
            val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = btManager?.adapter
            val bonded = adapter?.bondedDevices ?: emptySet()
            val list = bonded.map { device ->
                mapOf(
                    "name" to (device.name ?: "Bluetooth Printer"),
                    "address" to (device.address ?: "")
                )
            }.filter { (it["address"] ?: "").isNotEmpty() }
            result.success(list)
        } catch (e: SecurityException) {
            result.success(emptyList<Map<String, String>>())
        } catch (e: Exception) {
            result.success(emptyList<Map<String, String>>())
        }
    }
}
