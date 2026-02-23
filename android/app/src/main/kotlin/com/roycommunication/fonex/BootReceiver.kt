package com.roycommunication.fonex

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BootReceiver — listens for BOOT_COMPLETED to re-engage device lock after reboot.
 * Reads the persisted deviceLocked flag and relaunches the app if locked.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "FonexBootReceiver"
        private const val PREFS_NAME = "fonex_device_prefs"
        private const val KEY_DEVICE_LOCKED = "device_locked"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            Log.i(TAG, "System event received (${intent.action}) — restoring protection state")

            KeepAliveService.start(context)
            KeepAliveWatchdogWorker.schedule(context)
            DeviceLockManager(context).enforceFactoryResetBlock()

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val isLocked = prefs.getBoolean(KEY_DEVICE_LOCKED, false)

            if (isLocked) {
                Log.i(TAG, "Device is locked — launching FONEX to re-engage lock")
                launchApp(context)
            } else {
                Log.i(TAG, "Device is not locked — no action needed")
            }
        }
    }

    private fun launchApp(context: Context) {
        try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            launchIntent?.let {
                it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                context.startActivity(it)
                Log.i(TAG, "App launched successfully after boot")
            } ?: run {
                Log.e(TAG, "Could not get launch intent for package")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch app after boot: ${e.message}", e)
        }
    }
}
