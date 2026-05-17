package com.signalsight.signalsight

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // WiFi scan (Dashboard / Heatmap RSSI)
        MethodChannel(messenger, "com.signalsight/wifi")
            .setMethodCallHandler(WifiScanPlugin(applicationContext))

        // Network device discovery – now also owns "com.signalsight/network_stream" EventChannel
        MethodChannel(messenger, "com.signalsight/network")
            .setMethodCallHandler(NetworkScanPlugin(applicationContext, messenger))

        // PDR sensor stream – owns "com.signalsight/sensors/events" EventChannel
        MethodChannel(messenger, "com.signalsight/sensors")
            .setMethodCallHandler(SensorPlugin(applicationContext, messenger))
    }
}
