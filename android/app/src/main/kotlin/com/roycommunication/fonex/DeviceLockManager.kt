package com.roycommunication.fonex

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.UserManager
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController

/**
 * DeviceLockManager — manages Lock Task mode using DevicePolicyManager.
 * Handles enabling/disabling device lock, status bar control, and immersive mode.
 * Does NOT use root or Accessibility services.
 */
class DeviceLockManager(private val context: Context) {

    companion object {
        private const val TAG = "DeviceLockManager"
        private const val PREFS_NAME = "fonex_device_prefs"
        private const val KEY_DEVICE_LOCKED = "device_locked"
    }

    private val devicePolicyManager: DevicePolicyManager =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    private val adminComponent: ComponentName =
        MyDeviceAdminReceiver.getComponentName(context)

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * Check if this app is the Device Owner.
     */
    fun isDeviceOwner(): Boolean {
        return devicePolicyManager.isDeviceOwnerApp(context.packageName)
    }

    /**
     * Enable device lock — enters Lock Task mode using DevicePolicyManager.
     * Requires Device Owner privilege.
     */
    fun enableDeviceLock(activity: Activity): Boolean {
        if (!isDeviceOwner()) {
            Log.e(TAG, "Cannot enable device lock: app is not Device Owner")
            return false
        }

        try {
            // Whitelist this package for Lock Task
            devicePolicyManager.setLockTaskPackages(
                adminComponent,
                arrayOf(context.packageName)
            )

            // Configure lock task features — disable all escape mechanisms
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                devicePolicyManager.setLockTaskFeatures(
                    adminComponent,
                    DevicePolicyManager.LOCK_TASK_FEATURE_NONE
                )
            }

            // Apply critical User Restrictions (Block Factory Reset, Safe Mode, ADB, etc.)
            devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_FACTORY_RESET)
            devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_SAFE_BOOT)
            devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_DEBUGGING_FEATURES)
            devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_ADD_USER)

            // Enforce automatic time to prevent local timer tampering
            devicePolicyManager.setGlobalSetting(adminComponent, android.provider.Settings.Global.AUTO_TIME, "1")
            devicePolicyManager.setAutoTimeRequired(adminComponent, true)


            // Start Lock Task
            activity.startLockTask()

            // Disable status bar expansion
            disableStatusBar(activity)

            // Enable immersive mode
            enableImmersiveMode(activity)

            // Persist locked state
            setDeviceLockedFlag(true)

            Log.i(TAG, "Device lock ENABLED successfully")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enable device lock: ${e.message}", e)
            return false
        }
    }

    /**
     * Disable device lock — exits Lock Task mode and restores normal operation.
     */
    fun disableDeviceLock(activity: Activity): Boolean {
        try {
            // Stop Lock Task
            activity.stopLockTask()

            // Restore status bar
            restoreStatusBar(activity)

            // Remove User Restrictions
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_FACTORY_RESET)
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_SAFE_BOOT)
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_DEBUGGING_FEATURES)
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_ADD_USER)

            // Exit immersive mode
            disableImmersiveMode(activity)

            // Update persisted state
            setDeviceLockedFlag(false)

            Log.i(TAG, "Device lock DISABLED successfully")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to disable device lock: ${e.message}", e)
            return false
        }
    }

    /**
     * Check if the device is currently in locked state (from persisted flag).
     */
    fun isDeviceLocked(): Boolean {
        return prefs.getBoolean(KEY_DEVICE_LOCKED, false)
    }

    /**
     * Set the device locked flag in SharedPreferences.
     */
    fun setDeviceLockedFlag(locked: Boolean) {
        prefs.edit().putBoolean(KEY_DEVICE_LOCKED, locked).apply()
    }

    /**
     * Disable status bar to prevent notification shade pull-down.
     */
    private fun disableStatusBar(activity: Activity) {
        try {
            if (isDeviceOwner()) {
                devicePolicyManager.setStatusBarDisabled(adminComponent, true)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not disable status bar: ${e.message}")
        }
    }

    /**
     * Restore status bar to normal.
     */
    private fun restoreStatusBar(activity: Activity) {
        try {
            if (isDeviceOwner()) {
                devicePolicyManager.setStatusBarDisabled(adminComponent, false)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not restore status bar: ${e.message}")
        }
    }

    /**
     * Enable immersive sticky mode (hides navigation and status bars).
     */
    private fun enableImmersiveMode(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.systemBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            activity.window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
            )
        }
    }

    /**
     * Disable immersive mode and show system bars.
     */
    private fun disableImmersiveMode(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.window.insetsController?.show(WindowInsets.Type.systemBars())
        } else {
            @Suppress("DEPRECATION")
            activity.window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }
    }
}
