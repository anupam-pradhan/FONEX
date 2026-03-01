package com.roycommunication.fonex

import android.accounts.AccountManager
import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
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
        private val WALLPAPER_PICKER_PACKAGES = listOf(
            "com.google.android.apps.wallpaper",
            "com.android.wallpaper",
            "com.android.wallpaper.livepicker",
            "com.android.wallpaperpicker",
            "com.miui.miwallpaper",
            "com.xiaomi.thememanager",
            "com.samsung.android.app.dressroom",
            "com.samsung.android.dynamiclock",
            "com.samsung.android.themestore",
            "com.samsung.android.app.wallpaperchooser",
            "com.heytap.themestore",
            "com.coloros.wallpaper",
            "com.vivo.thememanager"
        )
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

    private fun isDebuggableBuild(): Boolean {
        return (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
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
            if (!isDebuggableBuild()) {
                devicePolicyManager.addUserRestriction(
                    adminComponent,
                    UserManager.DISALLOW_DEBUGGING_FEATURES
                )
            } else {
                Log.i(TAG, "Debug build: keeping USB debugging enabled while locked")
            }
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
            setBackupServiceEnabledInternal(enabled = true)
            setWallpaperPickerAppsHidden(hidden = true)

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
            enforceHomeLauncherForCurrentState()

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

            // Clear Lock Task packages so app cannot accidentally re-enter lock task
            try {
                if (isDeviceOwner()) {
                    devicePolicyManager.setLockTaskPackages(adminComponent, arrayOf())
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not clear lock task packages: ${e.message}")
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
                if (isPaidInFull) {
                    devicePolicyManager.clearUserRestriction(adminComponent, RESTRICTION_NO_SET_WALLPAPER)
                } else {
                    devicePolicyManager.addUserRestriction(adminComponent, RESTRICTION_NO_SET_WALLPAPER)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not update wallpaper restriction: ${e.message}")
            }
            setWallpaperPickerAppsHidden(hidden = !isPaidInFull)
            allowNormalGoogleAccounts(blockManagedProfile = !isPaidInFull)
            setBackupServiceEnabledInternal(enabled = true)
            devicePolicyManager.setMaximumTimeToLock(adminComponent, 0L)

            // Exit immersive mode
            disableImmersiveMode(activity)

            // Update persisted state
            setDeviceLockedFlag(false)
            // Record unlock timestamp to prevent race re-lock
            prefs.edit().putLong("last_unlock_ms", System.currentTimeMillis()).apply()
            enforceHomeLauncherForCurrentState()

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

    private fun isLockTaskModeActive(): Boolean {
        return try {
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            activityManager.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_LOCKED
        } catch (_: Exception) {
            false
        }
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
                setWallpaperPickerAppsHidden(hidden = false)
                allowNormalGoogleAccounts(blockManagedProfile = false)
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
                val isPaidInFull = prefs.getBoolean("is_paid_in_full", false)
                // Ensure account login flow is not blocked by this DPC.
                allowNormalGoogleAccounts(blockManagedProfile = !isPaidInFull)
                setBackupServiceEnabledInternal(enabled = true)
                if (!isPaidInFull) {
                    // Re-apply restrictions if not paid.
                    devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_FACTORY_RESET)
                    devicePolicyManager.addUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                    try {
                        devicePolicyManager.addUserRestriction(adminComponent, RESTRICTION_NO_SET_WALLPAPER)
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not enforce wallpaper change block: ${e.message}")
                    }
                    setWallpaperPickerAppsHidden(hidden = true)
                    Log.i(TAG, "Factory reset blocking enforced (EMI not paid)")
                    true
                } else {
                    // Remove restrictions only after full payment.
                    devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_FACTORY_RESET)
                    devicePolicyManager.clearUserRestriction(adminComponent, UserManager.DISALLOW_UNINSTALL_APPS)
                    try {
                        devicePolicyManager.clearUserRestriction(adminComponent, RESTRICTION_NO_SET_WALLPAPER)
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not clear wallpaper change block: ${e.message}")
                    }
                    setWallpaperPickerAppsHidden(hidden = false)
                    Log.i(TAG, "Factory reset allowed (EMI paid in full)")
                    false
                }
            } else {
                Log.w(TAG, "Cannot enforce restrictions: app is not Device Owner")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error enforcing factory reset block: ${e.message}")
            false
        }
    }

    /**
     * Force FONEX as HOME launcher while EMI is unpaid so warning UI cannot be removed.
     * Clears the persistent HOME mapping once paid in full.
     */
    fun enforceHomeLauncher(unpaidMode: Boolean): Boolean {
        return try {
            if (!isDeviceOwner()) return false

            // Always clear previous mapping first to avoid stale state.
            devicePolicyManager.clearPackagePersistentPreferredActivities(
                adminComponent,
                context.packageName
            )

            // During debug/testing, do not force FONEX as HOME launcher.
            // This avoids trapping navigation while validating command flows.
            if (isDebuggableBuild()) {
                // Also clear user-level preferred HOME selection for this package.
                // Without this, pressing Home can continue reopening FONEX in debug.
                try {
                    context.packageManager.clearPackagePreferredActivities(context.packageName)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not clear preferred home activities (debug): ${e.message}")
                }
                Log.i(TAG, "Debug build: skipping persistent HOME launcher enforcement")
                return true
            }

            if (unpaidMode) {
                val filter = IntentFilter(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    addCategory(Intent.CATEGORY_DEFAULT)
                }
                val homeActivity = ComponentName(context, MainActivity::class.java)
                devicePolicyManager.addPersistentPreferredActivity(
                    adminComponent,
                    filter,
                    homeActivity
                )
                Log.i(TAG, "Persistent HOME launcher enforced for unpaid mode")
            } else {
                // Clear user-level preferred HOME selection when unlocked/paid so
                // Android launcher choice returns to normal behavior.
                try {
                    context.packageManager.clearPackagePreferredActivities(context.packageName)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not clear preferred home activities: ${e.message}")
                }
                Log.i(TAG, "Persistent HOME launcher cleared (paid mode)")
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enforce HOME launcher policy: ${e.message}", e)
            false
        }
    }

    /**
     * Enforce HOME launcher only while unpaid AND actively locked.
     * This keeps normal Android home behavior in unpaid-but-unlocked mode.
     */
    fun enforceHomeLauncherForCurrentState(): Boolean {
        val isPaidInFull = prefs.getBoolean("is_paid_in_full", false)
        val isLockedFlag = isDeviceLocked()
        val lockTaskActive = isLockTaskModeActive()

        if (isLockedFlag && !lockTaskActive) {
            // Stale flag can otherwise trap users on FONEX home unexpectedly.
            setDeviceLockedFlag(false)
            Log.w(TAG, "Cleared stale lock flag: lock task is not active")
        }

        return enforceHomeLauncher(
            unpaidMode = !isPaidInFull && isLockedFlag && lockTaskActive,
        )
    }

    /**
     * Force-clear all restrictive policies for paid-in-full mode.
     * Keeps Device Owner but removes lock-task restrictions and account friction.
     */
    fun enforcePaidInFullState(activity: Activity? = null): Boolean {
        return try {
            if (!isDeviceOwner()) return false

            // Mark unlocked first so any policy re-check uses paid/unlocked state.
            setDeviceLockedFlag(false)
            prefs.edit().putLong("last_unlock_ms", System.currentTimeMillis()).apply()

            // Best-effort exit lock task and immersive mode.
            if (activity != null) {
                try {
                    activity.stopLockTask()
                } catch (_: Exception) {}
                disableImmersiveMode(activity)
                restoreStatusBar(activity)
            } else {
                try {
                    devicePolicyManager.setStatusBarDisabled(adminComponent, false)
                } catch (_: Exception) {}
            }

            try {
                devicePolicyManager.setLockTaskPackages(adminComponent, arrayOf())
            } catch (_: Exception) {}

            val restrictionsToClear = listOf(
                UserManager.DISALLOW_FACTORY_RESET,
                UserManager.DISALLOW_UNINSTALL_APPS,
                UserManager.DISALLOW_SAFE_BOOT,
                UserManager.DISALLOW_DEBUGGING_FEATURES,
                UserManager.DISALLOW_ADD_USER,
                UserManager.DISALLOW_REMOVE_USER,
                UserManager.DISALLOW_CONFIG_WIFI,
                UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS,
                UserManager.DISALLOW_MODIFY_ACCOUNTS,
                UserManager.DISALLOW_CONFIG_CREDENTIALS,
                UserManager.DISALLOW_REMOVE_MANAGED_PROFILE,
                UserManager.DISALLOW_ADD_MANAGED_PROFILE
            )
            restrictionsToClear.forEach { restriction ->
                try {
                    devicePolicyManager.clearUserRestriction(adminComponent, restriction)
                } catch (_: Exception) {}
            }
            try {
                devicePolicyManager.clearUserRestriction(adminComponent, RESTRICTION_NO_SET_WALLPAPER)
            } catch (_: Exception) {}

            try {
                devicePolicyManager.setMaximumTimeToLock(adminComponent, 0L)
            } catch (_: Exception) {}

            setWallpaperPickerAppsHidden(hidden = false)
            allowNormalGoogleAccounts(blockManagedProfile = false)
            setBackupServiceEnabledInternal(enabled = true)
            enforceHomeLauncher(unpaidMode = false)

            Log.i(TAG, "Paid-in-full policy applied: all lock restrictions cleared")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply paid-in-full policy: ${e.message}", e)
            false
        }
    }

    /**
     * Returns current backup service status if available.
     * On Android 12+ uses DevicePolicyManager backup APIs.
     * On older versions, checks secure setting backup_enabled when readable.
     */
    fun isGoogleBackupEnabled(): Boolean {
        return try {
            if (!isDeviceOwner()) return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                devicePolicyManager.isBackupServiceEnabled(adminComponent)
            } else {
                Settings.Secure.getInt(
                    context.contentResolver,
                    "backup_enabled",
                    1
                ) == 1
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not read backup service state: ${e.message}")
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

    private fun allowNormalGoogleAccounts(blockManagedProfile: Boolean = true) {
        // =====================================================================
        // FIX: Play Store "Sign in with work account" issue.
        //
        // In Device Owner mode Android treats the device as fully-managed, so
        // GMS/Play Store shows the enterprise sign-in flow.  The old approach
        // of blocking specific work account types via setAccountManagementDisabled
        // did NOT help (it's the Device Owner status itself that triggers the
        // work-account UI) and could actually *worsen* the problem on some OEMs
        // by confusing the Google Account Manager.
        //
        // New approach:
        //  1. Clear ALL account-related user restrictions.
        //  2. Enable ALL account types (including any previously-blocked ones).
        //  3. Prevent managed-profile creation (keeps things personal-only).
        //  4. Set affiliation IDs so GMS treats the primary user as the
        //     owner's own user, not an enterprise-provisioned profile.
        //  5. Unhide Play Store & Google Account packages.
        // =====================================================================

        // --- 1. Clear every restriction that can interfere with account sign-in ---
        val restrictionsToClear = listOf(
            UserManager.DISALLOW_MODIFY_ACCOUNTS,
            UserManager.DISALLOW_CONFIG_CREDENTIALS,
            UserManager.DISALLOW_REMOVE_MANAGED_PROFILE
        )
        restrictionsToClear.forEach { restriction ->
            try {
                devicePolicyManager.clearUserRestriction(adminComponent, restriction)
            } catch (e: Exception) {
                Log.w(TAG, "Could not clear restriction '$restriction': ${e.message}")
            }
        }

        // --- 2. Enable ALL account types (un-block any previously blocked ones) ---
        // First, explicitly enable Google accounts.
        try {
            devicePolicyManager.setAccountManagementDisabled(
                adminComponent, GOOGLE_ACCOUNT_TYPE, false
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not enable Google account type: ${e.message}")
        }
        // Then enable every authenticator type present on the device.
        try {
            val authenticators = AccountManager.get(context).authenticatorTypes
            authenticators.forEach { auth ->
                try {
                    devicePolicyManager.setAccountManagementDisabled(
                        adminComponent, auth.type, false
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "Could not enable account type '${auth.type}': ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not enumerate authenticator types: ${e.message}")
        }

        // --- 3. Optionally block managed/work profile creation.
        // In paid mode we keep this unrestricted.
        try {
            if (blockManagedProfile) {
                devicePolicyManager.addUserRestriction(
                    adminComponent, UserManager.DISALLOW_ADD_MANAGED_PROFILE
                )
            } else {
                devicePolicyManager.clearUserRestriction(
                    adminComponent, UserManager.DISALLOW_ADD_MANAGED_PROFILE
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not update managed-profile policy: ${e.message}")
        }

        // --- 4. Set affiliation IDs (Android 8+).  Tells GMS this primary user
        //        belongs to the management entity, which makes some GMS components
        //        treat the account flow more like a personal device. ---
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                devicePolicyManager.setAffiliationIds(
                    adminComponent, setOf("fonex-emi-personal-device")
                )
                Log.i(TAG, "Affiliation IDs set for personal-device mode")
            } catch (e: Exception) {
                Log.w(TAG, "Could not set affiliation IDs: ${e.message}")
            }
        }

        // --- 5. Unhide Play Store & key Google packages so they work normally ---
        val googlePackagesToUnhide = listOf(
            "com.android.vending",                  // Play Store
            "com.google.android.gms",               // Google Play Services
            "com.google.android.gsf",               // Google Services Framework
            "com.google.android.gsf.login",          // Google Account login helper
            "com.google.android.accounts"            // Google Account Manager (some OEMs)
        )
        googlePackagesToUnhide.forEach { pkg ->
            try {
                if (devicePolicyManager.isApplicationHidden(adminComponent, pkg)) {
                    devicePolicyManager.setApplicationHidden(adminComponent, pkg, false)
                    Log.i(TAG, "Unhid Google package: $pkg")
                }
            } catch (_: Exception) {
                // Package may not exist on this device — ignore.
            }
        }

        Log.i(TAG, "Account sign-in policy applied for personal-device mode")
    }

    private fun setBackupServiceEnabledInternal(enabled: Boolean): Boolean {
        if (!isDeviceOwner()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                devicePolicyManager.setBackupServiceEnabled(adminComponent, enabled)
                val status = devicePolicyManager.isBackupServiceEnabled(adminComponent)
                Log.i(TAG, "Google backup service status set: requested=$enabled actual=$status")
                status == enabled
            } else {
                // Best effort on pre-Android 12 devices.
                try {
                    devicePolicyManager.setSecureSetting(
                        adminComponent,
                        "backup_enabled",
                        if (enabled) "1" else "0"
                    )
                } catch (_: Exception) {
                    Settings.Secure.putInt(
                        context.contentResolver,
                        "backup_enabled",
                        if (enabled) 1 else 0
                    )
                }
                true
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not update backup service state: ${e.message}")
            false
        }
    }

    private fun setWallpaperPickerAppsHidden(hidden: Boolean) {
        if (!isDeviceOwner()) return
        WALLPAPER_PICKER_PACKAGES.forEach { packageName ->
            try {
                val currentHidden = devicePolicyManager.isApplicationHidden(adminComponent, packageName)
                if (currentHidden != hidden) {
                    devicePolicyManager.setApplicationHidden(adminComponent, packageName, hidden)
                    Log.i(TAG, "Wallpaper app '$packageName' hidden=$hidden")
                }
            } catch (e: Exception) {
                // Ignore missing packages or OEM restrictions.
                Log.d(TAG, "Wallpaper app policy skipped for '$packageName': ${e.message}")
            }
        }
    }
}
