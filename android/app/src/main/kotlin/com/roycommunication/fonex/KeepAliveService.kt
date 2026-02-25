package com.roycommunication.fonex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Foreground keep-alive service to reduce OEM background process kills.
 * This service does not poll commands; it only keeps the process healthy.
 */
class KeepAliveService : Service() {

    companion object {
        private const val TAG = "FonexKeepAliveService"
        private const val CHANNEL_ID = "fonex_keepalive_channel"
        private const val CHANNEL_NAME = "FONEX Protection"
        private const val NOTIFICATION_ID = 2207

        fun start(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildNotification())
        reEnforcePolicies()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        reEnforcePolicies()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        createNotificationChannel()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FONEX active")
            .setContentText("Device protection service is running")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "Keeps FONEX protection active in background"
        manager.createNotificationChannel(channel)
    }

    private fun reEnforcePolicies() {
        try {
            val manager = DeviceLockManager(applicationContext)
            if (!manager.isDeviceOwner()) return
            val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
            val isPaidInFull = prefs.getBoolean("is_paid_in_full", false)
            manager.enforceFactoryResetBlock()
            manager.enforceHomeLauncherForCurrentState()
            Log.i(TAG, "Policies re-enforced from keep-alive service. paidInFull=$isPaidInFull")
        } catch (e: Exception) {
            Log.w(TAG, "Policy re-enforcement failed: ${e.message}")
        }
    }
}
