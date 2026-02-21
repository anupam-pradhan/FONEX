package com.roycommunication.fonex

import android.os.Bundle
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import android.content.Context
import android.telephony.TelephonyManager
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deviceLockManager = DeviceLockManager(applicationContext)

        // If device was locked before (e.g., after reboot), re-engage lock task
        if (deviceLockManager.isDeviceLocked() && deviceLockManager.isDeviceOwner()) {
            Log.i(TAG, "Device locked state detected — re-engaging lock")
            deviceLockManager.enableDeviceLock(this)
            // Enable wake lock and keep screen on when locked
            enableWakeLock()
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
                    if (success) {
                        enableWakeLock() // Enable wake lock when device is locked
                    }
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

                else -> {
                    result.notImplemented()
                }
            }
        }
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
