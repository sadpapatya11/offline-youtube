package com.offlineyoutube.offlineyoutube

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import java.util.concurrent.atomic.AtomicInteger

object ThermalManager {
    private const val TAG = "ThermalManager"

    // Thermal statuses mirroring PowerManager.OnThermalStatusChangedListener
    const val THERMAL_STATUS_NONE = 0
    const val THERMAL_STATUS_LIGHT = 1
    const val THERMAL_STATUS_MODERATE = 2
    const val THERMAL_STATUS_SEVERE = 3
    const val THERMAL_STATUS_CRITICAL = 4
    const val THERMAL_STATUS_EMERGENCY = 5
    const val THERMAL_STATUS_SHUTDOWN = 6

    private val currentThermalStatus = AtomicInteger(THERMAL_STATUS_NONE)
    private var isRegistered = false

    fun init(context: Context) {
        if (isRegistered) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                if (powerManager != null) {
                    currentThermalStatus.set(powerManager.currentThermalStatus)
                    powerManager.addThermalStatusListener { status ->
                        val oldStatus = currentThermalStatus.getAndSet(status)
                        if (oldStatus != status) {
                            Log.i(TAG, "Device thermal status changed: $oldStatus -> $status (${getThermalStatusName(status)})")
                        }
                    }
                    isRegistered = true
                    Log.i(TAG, "ThermalManager initialized successfully. Initial status: ${getThermalStatusName(currentThermalStatus.get())}")
                }
            } else {
                Log.i(TAG, "Thermal API not supported on Android < Q (API 29). Running in standard power mode.")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register thermal status listener: ${e.message}")
        }
    }

    fun getThermalStatus(): Int = currentThermalStatus.get()

    fun getRecommendedLimitRate(): String {
        return when (currentThermalStatus.get()) {
            THERMAL_STATUS_NONE, THERMAL_STATUS_LIGHT -> "3.5M"
            THERMAL_STATUS_MODERATE -> "2.0M"
            THERMAL_STATUS_SEVERE -> "1.0M"
            THERMAL_STATUS_CRITICAL, THERMAL_STATUS_EMERGENCY, THERMAL_STATUS_SHUTDOWN -> "500K"
            else -> "3.5M"
        }
    }

    fun getRecommendedFfmpegThreads(): Int {
        return when (currentThermalStatus.get()) {
            THERMAL_STATUS_NONE, THERMAL_STATUS_LIGHT -> 2
            else -> 1 // Use single thread on warm device to stay on efficiency core
        }
    }

    fun isThermalCritical(): Boolean {
        val status = currentThermalStatus.get()
        return status >= THERMAL_STATUS_SEVERE
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
