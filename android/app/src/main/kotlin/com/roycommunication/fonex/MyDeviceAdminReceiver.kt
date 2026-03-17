package com.roycommunication.fonex

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.Toast

/**
 * Device Admin Receiver for FONEX Device Control.
 * Handles Device Owner / Device Admin callbacks.
 * onDisableRequested — blocks the user from removing FONEX as device admin while locked.
 */
class MyDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "FonexDeviceAdmin"
        private const val PREFS_NAME = "fonex_device_prefs"
        private const val KEY_DEVICE_LOCKED = "device_locked"
        private const val SUPPORT_STORE_NAME = "FONEX Powered by Roy Communication"

        fun getComponentName(context: Context): ComponentName {
            return ComponentName(context.applicationContext, MyDeviceAdminReceiver::class.java)
        }
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "Device admin enabled")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.i(TAG, "Device admin disabled")
        // Ensure warning wallpaper is removed immediately if admin/owner is disabled externally.
        try {
            val wallpaperManager = WallpaperManager.getInstance(context.applicationContext)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                wallpaperManager.clear(WallpaperManager.FLAG_SYSTEM)
                wallpaperManager.clear(WallpaperManager.FLAG_LOCK)
            } else {
                wallpaperManager.clear()
            }
            context
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean("warning_wallpaper_applied", false)
                .apply()
            Log.i(TAG, "Default wallpaper restored after admin disable")
        } catch (e: Exception) {
            Log.w(TAG, "Could not restore wallpaper after admin disable: ${e.message}")
        }
    }

    /**
     * Called when the user tries to disable this Device Admin from Settings.
     * If the device is currently locked (payment pending), we refuse and show a message.
     * The return value is shown to the user by Android before they confirm removal.
     */
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isLocked = prefs.getBoolean(KEY_DEVICE_LOCKED, false)

        return if (isLocked) {
            Log.w(TAG, "Admin disable requested — device is LOCKED, blocking.")
            Toast.makeText(
                context,
                "⚠️ Cannot remove FONEX admin — Please clear your due payment first and contact $SUPPORT_STORE_NAME.",
                Toast.LENGTH_LONG
            ).show()
            // This message will be shown in the Android confirmation dialog
            "⚠️ Device payment is pending. You cannot remove FONEX Device Admin until your due payment is completed. " +
            "Please visit $SUPPORT_STORE_NAME to unlock this device."
        } else {
            Log.i(TAG, "Admin disable requested — device is unlocked, allowing.")
            "Are you sure you want to remove FONEX device management?"
        }
    }

    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        super.onProfileProvisioningComplete(context, intent)
        Log.i(TAG, "Profile provisioning complete")

        // Set affiliation IDs as early as possible so GMS treats this as a
        // personal device rather than an enterprise-managed one.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                val admin = getComponentName(context)
                dpm.setAffiliationIds(admin, setOf("fonex-emi-personal-device"))
                Log.i(TAG, "Affiliation IDs set during provisioning")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not set affiliation IDs during provisioning: ${e.message}")
        }

        try {
            val manager = DeviceLockManager(context.applicationContext)
            manager.enforceFactoryResetBlock()
            manager.enforceHomeLauncherForCurrentState()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply post-provisioning policies: ${e.message}", e)
        }

        try {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }
            context.startActivity(launchIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch app after provisioning: ${e.message}", e)
        }
    }
}
