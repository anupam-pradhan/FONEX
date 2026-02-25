package com.roycommunication.fonex

import android.app.admin.DeviceAdminReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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
                "⚠️ Cannot remove FONEX admin — Please clear your due payment first and contact Roy Communication.",
                Toast.LENGTH_LONG
            ).show()
            // This message will be shown in the Android confirmation dialog
            "⚠️ Device payment is pending. You cannot remove FONEX Device Admin until your due payment is completed. " +
            "Please visit Roy Communication to unlock this device."
        } else {
            Log.i(TAG, "Admin disable requested — device is unlocked, allowing.")
            "Are you sure you want to remove FONEX device management?"
        }
    }

    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        super.onProfileProvisioningComplete(context, intent)
        Log.i(TAG, "Profile provisioning complete")
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
