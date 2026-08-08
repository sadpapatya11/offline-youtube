package com.offlineyoutube.offlineyoutube

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

object ThermalManager {
    private const val TAG = "ThermalManager"

    // Thermal statuses mirroring PowerManager.OnThermalStatusChangedListener (API 29+)
    const val THERMAL_STATUS_NONE = 0
    const val THERMAL_STATUS_LIGHT = 1
    const val THERMAL_STATUS_MODERATE = 2
    const val THERMAL_STATUS_SEVERE = 3
    const val THERMAL_STATUS_CRITICAL = 4
    const val THERMAL_STATUS_EMERGENCY = 5
    const val THERMAL_STATUS_SHUTDOWN = 6

    private val currentThermalStatus = AtomicInteger(THERMAL_STATUS_NONE)
    private val batteryTemperatureTenthsCelsius = AtomicInteger(300) // 30.0°C default
    private val isScreenOn = AtomicBoolean(true)
    private val isBatteryLow = AtomicBoolean(false)
    private var isRegistered = false

    private val thermalReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    isScreenOn.set(false)
                    // Set thread priority to background to enforce Linux CPU scheduler onto Efficiency (LITTLE) cores
                    try {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                    } catch (_: Exception) {}
                    Log.i(TAG, "Screen OFF detected -> Background priority enforced (EAS efficiency core bias)")
                }
                Intent.ACTION_SCREEN_ON -> {
                    isScreenOn.set(true)
                    try {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_DEFAULT)
                    } catch (_: Exception) {}
                    Log.i(TAG, "Screen ON detected -> Standard priority restored")
                }
                Intent.ACTION_BATTERY_CHANGED -> {
                    val temp = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 300)
                    batteryTemperatureTenthsCelsius.set(temp)
                    
                    val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                    val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                    val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
                    
                    if (level >= 0 && scale > 0) {
                        val pct = (level * 100) / scale
                        isBatteryLow.set(pct <= 15 && !isCharging)
                    }
                }
            }
        }
    }

    fun init(context: Context) {
        if (isRegistered) return
        val appContext = context.applicationContext
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val powerManager = appContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                if (powerManager != null) {
                    currentThermalStatus.set(powerManager.currentThermalStatus)
                    powerManager.addThermalStatusListener { status ->
                        val oldStatus = currentThermalStatus.getAndSet(status)
                        if (oldStatus != status) {
                            Log.i(TAG, "Device thermal status changed: $oldStatus -> $status (${getThermalStatusName(status)})")
                        }
                    }
                }
            }

            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_BATTERY_CHANGED)
            }
            appContext.registerReceiver(thermalReceiver, filter)
            isRegistered = true
            Log.i(TAG, "ThermalManager initialized. Initial status: ${getThermalStatusName(currentThermalStatus.get())}")
        } catch (e: Exception) {
            Log.w(TAG, "ThermalManager registration notice: ${e.message}")
        }
    }

    fun getThermalStatus(): Int = currentThermalStatus.get()

    fun getBatteryTemperatureCelsius(): Float = batteryTemperatureTenthsCelsius.get() / 10.0f

    fun isScreenActive(): Boolean = isScreenOn.get()

    fun isBatteryCriticallyLow(): Boolean = isBatteryLow.get()

    fun getRecommendedLimitRate(): String {
        val thermal = currentThermalStatus.get()
        val battTemp = getBatteryTemperatureCelsius()

        return when {
            thermal >= THERMAL_STATUS_CRITICAL || battTemp >= 45.0f -> "500K"
            thermal >= THERMAL_STATUS_SEVERE || battTemp >= 42.0f -> "1.0M"
            thermal >= THERMAL_STATUS_MODERATE || battTemp >= 38.5f || !isScreenOn.get() -> "2.0M"
            else -> "3.5M"
        }
    }

    fun getRecommendedFfmpegThreads(): Int {
        val thermal = currentThermalStatus.get()
        val battTemp = getBatteryTemperatureCelsius()
        // If device is warm, screen is off, or thermal status is elevated, cap FFmpeg to 1 thread on Little core
        return if (thermal >= THERMAL_STATUS_MODERATE || battTemp >= 38.5f || !isScreenOn.get()) {
            1
        } else {
            2
        }
    }

    fun isThermalCritical(): Boolean {
        return currentThermalStatus.get() >= THERMAL_STATUS_SEVERE || getBatteryTemperatureCelsius() >= 44.0f
    }

    fun getDiagnosticsReport(): Map<String, Any> {
        return mapOf(
            "thermalStatus" to getThermalStatusName(currentThermalStatus.get()),
            "batteryTempC" to getBatteryTemperatureCelsius(),
            "screenOn" to isScreenOn.get(),
            "limitRate" to getRecommendedLimitRate(),
            "ffmpegThreads" to getRecommendedFfmpegThreads()
        )
    }

    private fun getThermalStatusName(status: Int): String {
        return when (status) {
            THERMAL_STATUS_NONE -> "NORMAL (None)"
            THERMAL_STATUS_LIGHT -> "LIGHT"
            THERMAL_STATUS_MODERATE -> "MODERATE (Warm)"
            THERMAL_STATUS_SEVERE -> "SEVERE (Hot)"
            THERMAL_STATUS_CRITICAL -> "CRITICAL (Overheating)"
            THERMAL_STATUS_EMERGENCY -> "EMERGENCY"
            THERMAL_STATUS_SHUTDOWN -> "SHUTDOWN"
            else -> "UNKNOWN ($status)"
        }
    }
}
