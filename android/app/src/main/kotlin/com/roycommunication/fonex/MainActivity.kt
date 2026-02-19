package com.roycommunication.fonex

import android.os.Bundle
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deviceLockManager = DeviceLockManager(applicationContext)

        // If device was locked before (e.g., after reboot), re-engage lock task
        if (deviceLockManager.isDeviceLocked() && deviceLockManager.isDeviceOwner()) {
            Log.i(TAG, "Device locked state detected — re-engaging lock")
            deviceLockManager.enableDeviceLock(this)
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
                    val info = mapOf(
                        "isDeviceOwner" to deviceLockManager.isDeviceOwner(),
                        "isDeviceLocked" to deviceLockManager.isDeviceLocked(),
                        "androidVersion" to android.os.Build.VERSION.SDK_INT,
                        "deviceModel" to android.os.Build.MODEL,
                        "manufacturer" to android.os.Build.MANUFACTURER
                    )
                    result.success(info)
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
