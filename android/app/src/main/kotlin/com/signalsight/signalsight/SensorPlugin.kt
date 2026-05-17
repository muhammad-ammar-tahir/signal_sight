package com.signalsight.signalsight

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sin
import kotlin.math.cos

/**
 * SensorPlugin – Pedestrian Dead Reckoning (PDR) via EventChannel.
 *
 * MethodChannel  "com.signalsight/sensors"
 *   → startTracking            : begin step + heading listeners; hold wake lock
 *   → stopTracking             : unregister listeners; release wake lock
 *   → calibrateCompass         : reset heading to 0 (point phone north)
 *   → setStrideLength(double)  : override stride length (default 0.75 m)
 *
 * EventChannel   "com.signalsight/sensors/events"
 *   → emits Map on every step:
 *       { "x": totalX, "y": totalY, "heading": heading, "steps": totalSteps,
 *         "stepCount": totalSteps, "headingRadians": heading,
 *         "timestamp": millis }
 *
 * Sensors used:
 *   • TYPE_STEP_DETECTOR   – fires once per physical step
 *   • TYPE_ROTATION_VECTOR – fused heading (gyro + accel + mag)
 *     Fallback: complementary filter (gyro + accel/mag) if rotation vector unavailable
 */
class SensorPlugin(
    private val context: Context,
    private val binaryMessenger: io.flutter.plugin.common.BinaryMessenger
) : MethodChannel.MethodCallHandler, SensorEventListener {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val mainHandler   = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null

    // PDR state
    private var totalX = 0.0
    private var totalY = 0.0
    private var totalSteps = 0
    private var currentHeadingRadians = 0.0
    private var strideLength = 0.75



    // Wake lock – keeps CPU alive during mapping even with screen off
    private var wakeLock: PowerManager.WakeLock? = null

    init {
        EventChannel(binaryMessenger, "com.signalsight/sensors/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    // ── MethodChannel handler ─────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startTracking" -> {
                // Reset PDR state for new session
                totalX = 0.0
                totalY = 0.0
                totalSteps = 0
                currentHeadingRadians = 0.0
                acquireWakeLock()
                startSensors()
                result.success(null)
            }
            "stopTracking" -> {
                stopSensors()
                releaseWakeLock()
                result.success(null)
            }
            "calibrateCompass" -> {
                currentHeadingRadians = 0.0
                result.success(null)
            }
            "setStrideLength" -> {
                val sl = call.argument<Double>("strideLength")
                if (sl != null && sl > 0) strideLength = sl
                result.success(null)
            }
            "setTargetBssid" -> {
                // Accepted for API compatibility – RSSI is now fetched on Dart side
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Sensor registration ───────────────────────────────────────────────────

    private fun startSensors() {
        sensorManager.unregisterListener(this) // safety: clear stale listeners

        val stepDetector    = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        val rotationVector  = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

        if (stepDetector != null) {
            sensorManager.registerListener(this, stepDetector, SensorManager.SENSOR_DELAY_UI)
        }

        if (rotationVector != null) {
            sensorManager.registerListener(this, rotationVector, SensorManager.SENSOR_DELAY_GAME)
        }
    }

    private fun stopSensors() {
        sensorManager.unregisterListener(this)
    }

    // ── SensorEventListener ───────────────────────────────────────────────────

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {

            Sensor.TYPE_ROTATION_VECTOR -> {
                val rotMatrix = FloatArray(9)
                SensorManager.getRotationMatrixFromVector(rotMatrix, event.values)
                val orientation = FloatArray(3)
                SensorManager.getOrientation(rotMatrix, orientation)
                currentHeadingRadians = orientation[0].toDouble()
            }


            Sensor.TYPE_STEP_DETECTOR -> {
                totalSteps++
                // Update position using current heading and stride
                val heading = currentHeadingRadians
                totalX += sin(heading) * strideLength
                totalY += cos(heading) * strideLength

                val payload = mapOf(
                    "x"              to totalX,
                    "y"              to totalY,
                    "heading"        to heading,
                    "steps"          to totalSteps,
                    "stepCount"      to totalSteps,
                    "headingRadians" to heading,
                    "timestamp"      to System.currentTimeMillis()
                )

                mainHandler.post {
                    eventSink?.success(payload)
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // ── Wake lock ─────────────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "signalsight:HeatmapTracking"
        ).also { it.acquire(60 * 60 * 1000L) } // max 1 hour
    }

    private fun releaseWakeLock() {
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
    }
}
