package com.roycommunication.fonex

import android.accounts.AccountManager
import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.provider.Settings
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
        private const val RESTRICTION_NO_SET_WALLPAPER = "no_set_wallpaper"
        private const val GOOGLE_ACCOUNT_TYPE = "com.google"
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
            // Prevent app uninstallation
            devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
            // Prevent removing users (additional security)
            devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_REMOVE_USER)
            // Reduce chances of user disabling connectivity while locked
            devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_WIFI)
            devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS)
            // Prevent user from changing wallpaper while device is locked.
            try {
                devicePolicyManager.addUserRestriction(adminComponent, RESTRICTION_NO_SET_WALLPAPER)
            } catch (e: Exception) {
                Log.w(TAG, "Could not apply wallpaper restriction: ${e.message}")
            }
            // Keep personal Google account sign-in available.
            allowNormalGoogleAccounts()

            // Enforce automatic time to prevent local timer tampering
            devicePolicyManager.setGlobalSetting(adminComponent, android.provider.Settings.Global.AUTO_TIME, "1")
            devicePolicyManager.setAutoTimeRequired(adminComponent, true)
            // Auto-lock screen after 1 minute idle to save battery in locked mode.
            devicePolicyManager.setMaximumTimeToLock(adminComponent, 60_000L)


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
            try {
                activity.stopLockTask()
            } catch (e: Exception) {
                // Device might already be out of lock task mode; continue cleanup anyway.
                Log.w(TAG, "stopLockTask skipped: ${e.message}")
            }

            // Restore status bar
            restoreStatusBar(activity)

            // Remove User Restrictions (only if EMI is paid in full)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val isPaidInFull = prefs.getBoolean("is_paid_in_full", false)
            
            if (isPaidInFull) {
                // Allow factory reset and uninstall only after EMI is fully paid
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_FACTORY_RESET)
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
            }
            
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_SAFE_BOOT)
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_DEBUGGING_FEATURES)
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_ADD_USER)
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_REMOVE_USER)
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_WIFI)
            devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS)
            try {
                devicePolicyManager.clearUserRestriction(adminComponent, RESTRICTION_NO_SET_WALLPAPER)
            } catch (e: Exception) {
                Log.w(TAG, "Could not clear wallpaper restriction: ${e.message}")
            }
            allowNormalGoogleAccounts()
            devicePolicyManager.setMaximumTimeToLock(adminComponent, 0L)

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

    /**
     * Permanently remove Device Owner status (Paid in Full mode).
     * Also removes all restrictions to allow factory reset and uninstall.
     */
    fun clearDeviceOwner(): Boolean {
        return try {
            if (isDeviceOwner()) {
                // Remove all restrictions before clearing device owner
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_FACTORY_RESET)
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_SAFE_BOOT)
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_DEBUGGING_FEATURES)
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_ADD_USER)
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_REMOVE_USER)
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_WIFI)
                devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS)
                try {
                    devicePolicyManager.clearUserRestriction(adminComponent, RESTRICTION_NO_SET_WALLPAPER)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not clear wallpaper restriction: ${e.message}")
                }
                allowNormalGoogleAccounts()
                setDeviceLockedFlag(false)
                
                devicePolicyManager.clearDeviceOwnerApp(context.packageName)
                Log.i(TAG, "Device Owner status successfully cleared. Factory reset and uninstall now allowed.")
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear Device Owner: ${e.message}")
            false
        }
    }
    
    /**
     * Check if app uninstallation is blocked.
     */
    fun isUninstallBlocked(): Boolean {
        return try {
            if (isDeviceOwner()) {
                val restrictions = devicePolicyManager.getUserRestrictions(adminComponent)
                restrictions.containsKey(UserManager.DISALLOW_UNINSTALL_APPS)
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking uninstall block: ${e.message}")
            false
        }
    }
    
    /**
     * Check if factory reset is blocked.
     * Returns true if factory reset is blocked (EMI not paid), false if allowed (EMI paid).
     */
    fun isFactoryResetBlocked(): Boolean {
        return try {
            if (isDeviceOwner()) {
                val restrictions = devicePolicyManager.getUserRestrictions(adminComponent)
                val isBlocked = restrictions.containsKey(UserManager.DISALLOW_FACTORY_RESET)
                val isPaidInFull = prefs.getBoolean("is_paid_in_full", false)
                // Factory reset is blocked if restriction exists AND EMI is not paid
                isBlocked && !isPaidInFull
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking factory reset block: ${e.message}")
            false
        }
    }
    
    /**
     * Re-apply factory reset blocking if EMI is not paid.
     * Called after checking payment status from server.
     */
    fun enforceFactoryResetBlock(): Boolean {
        return try {
            if (isDeviceOwner()) {
                // Ensure account login flow is not blocked by this DPC.
                allowNormalGoogleAccounts()
                val isPaidInFull = prefs.getBoolean("is_paid_in_full", false)
                if (!isPaidInFull) {
                    // Re-apply restrictions if not paid.
                    devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_FACTORY_RESET)
                    devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                    Log.i(TAG, "Factory reset blocking enforced (EMI not paid)")
                    true
                } else {
                    // Remove restrictions only after full payment.
                    devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_FACTORY_RESET)
                    devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                    Log.i(TAG, "Factory reset allowed (EMI paid in full)")
                    false
                }
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error enforcing factory reset block: ${e.message}")
            false
        }
    }

    /**
     * Turn off the screen immediately while keeping lock mode active.
     */
    fun lockScreenNow(): Boolean {
        return try {
            if (!isDeviceOwner()) return false
            devicePolicyManager.lockNow()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to lock screen now: ${e.message}", e)
            false
        }
    }

    /**
     * Best-effort connectivity recovery for locked mode.
     * Note: Android 10+ may still restrict direct Wi-Fi toggling for non-system apps.
     */
    fun requestConnectivityRecovery(): Boolean {
        return try {
            if (!isDeviceOwner()) return false
            devicePolicyManager.setGlobalSetting(adminComponent, Settings.Global.WIFI_ON, "1")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Connectivity recovery via DPM failed: ${e.message}")
            false
        }
    }

    private fun allowNormalGoogleAccounts() {
        // Keep account sign-in open for personal Google accounts while retaining
        // EMI-related reset/uninstall restrictions.
        val accountRestrictions = listOf(
            UserManager.DISALLOW_MODIFY_ACCOUNTS,
            UserManager.DISALLOW_CONFIG_CREDENTIALS,
            UserManager.DISALLOW_ADD_MANAGED_PROFILE,
            UserManager.DISALLOW_REMOVE_MANAGED_PROFILE
        )
        accountRestrictions.forEach { restriction ->
            try {
                devicePolicyManager.clearUserRestriction(adminComponent, restriction)
            } catch (e: Exception) {
                Log.w(TAG, "Could not clear restriction '$restriction': ${e.message}")
            }
        }

        val accountTypes = mutableSetOf(
            GOOGLE_ACCOUNT_TYPE,
            "com.google.work",
            "com.android.exchange"
        )
        try {
            val authenticators = AccountManager.get(context).authenticatorTypes
            authenticators.forEach { accountTypes.add(it.type) }
        } catch (e: Exception) {
            Log.w(TAG, "Could not enumerate authenticator account types: ${e.message}")
        }

        accountTypes.forEach { accountType ->
            try {
                devicePolicyManager.setAccountManagementDisabled(
                    adminComponent,
                    accountType,
                    false
                )
            } catch (e: Exception) {
                Log.w(TAG, "Could not enable account management for '$accountType': ${e.message}")
            }
        }
    }
}
