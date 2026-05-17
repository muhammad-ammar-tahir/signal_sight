package com.signalsight.signalsight

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WifiScanPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    private val wifiManager: WifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startForegroundScan" -> {
                startScanService()
                triggerScan()
                result.success(null)
            }
            "stopForegroundScan" -> {
                stopScanService()
                result.success(null)
            }
            "getResults" -> {
                result.success(getScanResults())
            }
            "getConnectedBSSID" -> {
                result.success(getConnectedBSSID())
            }
            else -> result.notImplemented()
        }
    }

    private fun triggerScan() {
        if (!hasLocationPermission()) return
        @Suppress("DEPRECATION")
        wifiManager.startScan()
    }

    private fun startScanService() {
        val intent = Intent(context, WifiScanService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun stopScanService() {
        context.stopService(Intent(context, WifiScanService::class.java))
    }

    private fun getScanResults(): List<Map<String, Any>> {
        if (!hasLocationPermission()) return emptyList()
        val results = wifiManager.scanResults ?: return emptyList()
        return results.map { r ->
            mapOf(
                "SSID" to (r.SSID ?: ""),
                "BSSID" to (r.BSSID ?: ""),
                "level" to r.level,
                "frequency" to r.frequency,
                "capabilities" to (r.capabilities ?: "")
            )
        }
    }

    private fun getConnectedBSSID(): String? {
        if (!hasLocationPermission()) return null
        val info = wifiManager.connectionInfo ?: return null
        return info.bssid
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }
}
