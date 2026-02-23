package com.roycommunication.fonex

import android.os.Bundle
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.telephony.TelephonyManager
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — Flutter host activity with MethodChannel bridge.
 * Connects Flutter UI to native DeviceLockManager and EncryptedSharedPreferences.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "FonexMainActivity"
        private const val CHANNEL = "device.lock/channel"
        private const val ENCRYPTED_PREFS_NAME = "fonex_secure_prefs"
        private const val KEY_OWNER_PIN = "owner_pin"
        private const val DEFAULT_PIN = "1234"
    }

    private lateinit var deviceLockManager: DeviceLockManager
    private var wakeLock: PowerManager.WakeLock? = null

    // Use TextureView to avoid SurfaceView buffer issues on some OEM ROMs.
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deviceLockManager = DeviceLockManager(applicationContext)
        KeepAliveService.start(applicationContext)
        KeepAliveWatchdogWorker.schedule(applicationContext)

        // Ensure reset/uninstall protection persists across app restarts.
        if (deviceLockManager.isDeviceOwner()) {
            deviceLockManager.enforceFactoryResetBlock()
        }

        // If device was locked before (e.g., after reboot), re-engage lock task
        if (deviceLockManager.isDeviceLocked() && deviceLockManager.isDeviceOwner()) {
            Log.i(TAG, "Device locked state detected — re-engaging lock")
            deviceLockManager.enableDeviceLock(this)
        }
    }
    
    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }
    
    private fun enableWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "FONEX::WakeLock"
            )
            wakeLock?.acquire(10 * 60 * 60 * 1000L) // 10 hours
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            Log.i(TAG, "Wake lock enabled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enable wake lock: ${e.message}")
        }
    }
    
    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
            wakeLock = null
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            Log.i(TAG, "Wake lock released")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release wake lock: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceOwner" -> {
                    result.success(deviceLockManager.isDeviceOwner())
                }

                "startDeviceLock" -> {
                    val success = deviceLockManager.enableDeviceLock(this)
                    result.success(success)
                }

                "stopDeviceLock" -> {
                    val success = deviceLockManager.disableDeviceLock(this)
                    if (success) {
                        releaseWakeLock() // Release wake lock when device is unlocked
                    }
                    result.success(success)
                }

                "isDeviceLocked" -> {
                    result.success(deviceLockManager.isDeviceLocked())
                }

                "setDeviceLocked" -> {
                    val locked = call.argument<Boolean>("locked") ?: false
                    deviceLockManager.setDeviceLockedFlag(locked)
                    result.success(true)
                }

                "validatePin" -> {
                    val pin = call.argument<String>("pin") ?: ""
                    val storedPin = getOwnerPin()
                    result.success(pin == storedPin)
                }

                "setOwnerPin" -> {
                    val newPin = call.argument<String>("pin") ?: ""
                    if (newPin.length >= 4) {
                        setOwnerPin(newPin)
                        result.success(true)
                    } else {
                        result.error("INVALID_PIN", "PIN must be at least 4 digits", null)
                    }
                }

                "getDeviceInfo" -> {
                    val tm = applicationContext.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                    val imei = try {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            tm.imei
                        } else {
                            @Suppress("DEPRECATION", "MissingPermission")
                            tm.deviceId
                        }
                    } catch (e: SecurityException) {
                        "Permission Denied"
                    } catch (e: Exception) {
                        "Unknown API Error"
                    }

                    val info = mapOf(
                        "isDeviceOwner" to deviceLockManager.isDeviceOwner(),
                        "isDeviceLocked" to deviceLockManager.isDeviceLocked(),
                        "androidVersion" to android.os.Build.VERSION.SDK_INT,
                        "deviceModel" to android.os.Build.MODEL,
                        "manufacturer" to android.os.Build.MANUFACTURER,
                        "imei" to (imei ?: "Not Found")
                    )
                    result.success(info)
                }

                "getSimState" -> {
                    val tm = applicationContext.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                    result.success(tm.simState)
                }

                "getBatteryLevel" -> {
                    result.success(getBatteryLevel())
                }

                "startKeepAliveService" -> {
                    KeepAliveService.start(applicationContext)
                    result.success(true)
                }

                "scheduleKeepAliveWatchdog" -> {
                    KeepAliveWatchdogWorker.schedule(applicationContext)
                    result.success(true)
                }

                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }

                "openAutoStartSettings" -> {
                    result.success(openAutoStartSettings())
                }

                "showResetBlockedMessage" -> {
                    android.widget.Toast.makeText(
                        this,
                        "⛔ Cannot reset this device — Please complete your EMI payment first. " +
                        "Contact Roy Communication: +91 8388855549",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                    result.success(true)
                }

                "clearDeviceOwner" -> {
                    val success = deviceLockManager.clearDeviceOwner()
                    result.success(success)
                }

                "isUninstallBlocked" -> {
                    result.success(deviceLockManager.isUninstallBlocked())
                }

                "setPaidInFull" -> {
                    val paid = call.argument<Boolean>("paid") ?: false
                    val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("is_paid_in_full", paid).apply()
                    if (paid) {
                        // Remove restrictions when paid - allow factory reset and uninstall
                        deviceLockManager.disableDeviceLock(this)
                        deviceLockManager.enforceFactoryResetBlock() // This will remove the restriction
                    } else {
                        // Re-enforce restrictions if payment status changes
                        deviceLockManager.enforceFactoryResetBlock()
                    }
                    result.success(true)
                }
                
                "isFactoryResetBlocked" -> {
                    result.success(deviceLockManager.isFactoryResetBlocked())
                }
                
                "enforceFactoryResetBlock" -> {
                    result.success(deviceLockManager.enforceFactoryResetBlock())
                }

                "lockScreenNow" -> {
                    result.success(deviceLockManager.lockScreenNow())
                }

                "ensureConnectivityForLock" -> {
                    result.success(ensureConnectivityForLock())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun ensureConnectivityForLock(): Map<String, Any> {
        val alreadyConnected = isNetworkConnected()
        if (alreadyConnected) {
            return mapOf(
                "already_connected" to true,
                "attempted_recovery" to false,
                "connected_now" to true
            )
        }

        var attemptedRecovery = false
        attemptedRecovery = deviceLockManager.requestConnectivityRecovery() || attemptedRecovery

        // Best-effort Wi-Fi enable for Android versions that still allow it.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            try {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                if (!wifiManager.isWifiEnabled) {
                    attemptedRecovery = wifiManager.setWifiEnabled(true) || attemptedRecovery
                }
            } catch (e: Exception) {
                Log.w(TAG, "Wi-Fi enable attempt failed: ${e.message}")
            }
        }

        return mapOf(
            "already_connected" to false,
            "attempted_recovery" to attemptedRecovery,
            "connected_now" to isNetworkConnected()
        )
    }

    private fun isNetworkConnected(): Boolean {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (e: Exception) {
            Log.w(TAG, "Network check failed: ${e.message}")
            false
        }
    }

    private fun getBatteryLevel(): Int? {
        return try {
            val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (level in 0..100) {
                level
            } else {
                val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val fallbackLevel = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                if (fallbackLevel >= 0 && scale > 0) {
                    (fallbackLevel * 100) / scale
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reading battery level: ${e.message}", e)
            null
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) return true
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) return
        if (isIgnoringBatteryOptimizations()) return

        try {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request battery optimization exemption: ${e.message}", e)
            try {
                val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(fallbackIntent)
            } catch (_: Exception) {}
        }
    }

    private fun openAutoStartSettings(): Boolean {
        val intents = listOf(
            Intent().apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            },
            Intent().apply {
                component = ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
            },
            Intent().apply {
                component = ComponentName(
                    "com.oplus.safecenter",
                    "com.oplus.safecenter.startupapp.StartupAppListActivity"
                )
            },
            Intent().apply {
                component = ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                )
            },
            Intent().apply {
                component = ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                )
            },
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            },
        )

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Try next intent candidate.
            }
        }
        return false
    }

    /**
     * Get the owner PIN from EncryptedSharedPreferences.
     * Returns default PIN if not set.
     */
    private fun getOwnerPin(): String {
        return try {
            val masterKey = MasterKey.Builder(applicationContext)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            val encryptedPrefs = EncryptedSharedPreferences.create(
                applicationContext,
                ENCRYPTED_PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )

            encryptedPrefs.getString(KEY_OWNER_PIN, DEFAULT_PIN) ?: DEFAULT_PIN
        } catch (e: Exception) {
            Log.e(TAG, "Error reading encrypted PIN: ${e.message}", e)
            DEFAULT_PIN
        }
    }

    /**
     * Save the owner PIN to EncryptedSharedPreferences.
     */
    private fun setOwnerPin(pin: String) {
        try {
            val masterKey = MasterKey.Builder(applicationContext)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            val encryptedPrefs = EncryptedSharedPreferences.create(
                applicationContext,
                ENCRYPTED_PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )

            encryptedPrefs.edit().putString(KEY_OWNER_PIN, pin).apply()
            Log.i(TAG, "Owner PIN updated successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving encrypted PIN: ${e.message}", e)
        }
    }
}
