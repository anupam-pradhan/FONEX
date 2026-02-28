package com.roycommunication.fonex

import android.Manifest
import android.appwidget.AppWidgetManager
import android.app.WallpaperManager
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.telephony.TelephonyManager
import android.os.PowerManager
import android.provider.Settings
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

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
        private const val ORIGINAL_WALLPAPER_FILE = "original_system_wallpaper.png"
        private const val KEY_WIDGET_PIN_REQUESTED = "emi_widget_pin_requested"
        private const val KEY_WARNING_WALLPAPER_APPLIED = "warning_wallpaper_applied"
        private const val KEY_WARNING_WALLPAPER_VERSION = "warning_wallpaper_version"
        private const val KEY_WARNING_WALLPAPER_LAST_APPLIED_AT = "warning_wallpaper_last_applied_at"
        private const val WARNING_WALLPAPER_VERSION = 2
        private const val WARNING_WALLPAPER_REAPPLY_COOLDOWN_MS = 8_000L
        private const val REQUEST_CODE_POST_NOTIFICATIONS = 6013
        private const val SUPPORT_STORE_NAME = "Roy Communication"
        private const val SUPPORT_PHONE_1 = "+91 8388855549"
        private const val SUPPORT_PHONE_2 = "+91 9635252455"
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
        requestNotificationPermissionIfNeeded()
        val paidInFull = isPaidInFull()

        // Ensure reset/uninstall protection persists across app restarts.
        if (deviceLockManager.isDeviceOwner()) {
            deviceLockManager.enforceFactoryResetBlock()
            deviceLockManager.enforceHomeLauncherForCurrentState()

            // If device was locked before (e.g., after reboot), re-engage lock task
            // But NOT if device was just unlocked (prevents race condition)
            val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
            val lastUnlockMs = prefs.getLong("last_unlock_ms", 0L)
            val msSinceUnlock = System.currentTimeMillis() - lastUnlockMs
            if (!paidInFull && deviceLockManager.isDeviceLocked() && msSinceUnlock > 30_000L) {
                Log.i(TAG, "Device locked state detected — re-engaging lock")
                deviceLockManager.enableDeviceLock(this)
            } else if (deviceLockManager.isDeviceLocked() && (paidInFull || msSinceUnlock <= 30_000L)) {
                Log.i(TAG, "Device locked flag found but recently unlocked — clearing stale flag")
                deviceLockManager.setDeviceLockedFlag(false)
                deviceLockManager.enforceHomeLauncherForCurrentState()
            }
        }

        if (!paidInFull) {
            // Apply generated warning wallpaper in unpaid mode.
            applyWarningSystemWallpaper(refreshBackup = false)
        } else {
            restoreOriginalSystemWallpaper()
        }
        refreshHomeWarningWidget()
        if (!paidInFull) {
            requestPinWarningWidgetIfSupported()
        }
    }

    override fun onResume() {
        super.onResume()
        if (deviceLockManager.isDeviceOwner()) {
            // Re-apply unpaid protections and account-login allowance on every resume.
            deviceLockManager.enforceFactoryResetBlock()
            // Don't re-enforce home launcher if device was recently unlocked
            // (prevents race condition that traps user in FONEX after unlock)
            val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
            val lastUnlockMs = prefs.getLong("last_unlock_ms", 0L)
            val msSinceUnlock = System.currentTimeMillis() - lastUnlockMs
            if (msSinceUnlock > 30_000L) {
                deviceLockManager.enforceHomeLauncherForCurrentState()
            }
        }
        if (isPaidInFull()) {
            restoreOriginalSystemWallpaper()
        } else {
            // Keep generated warning wallpaper visible in unpaid mode.
            applyWarningSystemWallpaper(refreshBackup = false)
            requestPinWarningWidgetIfSupported()
        }
        refreshHomeWarningWidget()
    }
    
    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.i(TAG, "POST_NOTIFICATIONS permission result: granted=$granted")
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return

        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_CODE_POST_NOTIFICATIONS
        )
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
                        applyWarningSystemWallpaper(refreshBackup = true)
                    }
                    result.success(success)
                }

                "stopDeviceLock" -> {
                    val success = deviceLockManager.disableDeviceLock(this)
                    if (success) {
                        restoreOriginalSystemWallpaper()
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

                "openAddAccountSettings" -> {
                    result.success(openAddAccountSettings())
                }

                "showResetBlockedMessage" -> {
                    android.widget.Toast.makeText(
                        this,
                        "⛔ Cannot reset this device — Please clear your due payment first. " +
                        "Contact $SUPPORT_STORE_NAME: $SUPPORT_PHONE_1, $SUPPORT_PHONE_2",
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
                    if (deviceLockManager.isDeviceOwner()) {
                        deviceLockManager.enforceHomeLauncherForCurrentState()
                    }
                    if (paid) {
                        // Remove lock mode and restrictions once payment is fully completed.
                        deviceLockManager.disableDeviceLock(this)
                        deviceLockManager.setDeviceLockedFlag(false)
                        restoreOriginalSystemWallpaper()
                        releaseWakeLock()
                        // Keep Device Owner active so management can be re-applied if needed.
                        // Paid mode still clears reset/uninstall restrictions via enforceFactoryResetBlock().
                        deviceLockManager.enforceFactoryResetBlock()
                        Log.i(TAG, "Paid-in-full mode enabled. Device Owner retained.")
                    } else {
                        // Re-enforce restrictions if payment status changes
                        deviceLockManager.enforceFactoryResetBlock()
                        applyWarningSystemWallpaper(refreshBackup = false)
                        requestPinWarningWidgetIfSupported()
                    }
                    refreshHomeWarningWidget()
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

                "showCommandNotification" -> {
                    val title = call.argument<String>("title") ?: "FONEX"
                    val body = call.argument<String>("body") ?: ""
                    showCommandNotification(title, body)
                    result.success(true)
                }

                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun showCommandNotification(title: String, body: String) {
        try {
            val channelId = "fonex_command_channel"
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            val notificationsEnabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
            if (!notificationsEnabled) {
                Log.w(TAG, "Skipping command notification: app notifications are disabled")
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
                if (!granted) {
                    Log.w(TAG, "Skipping command notification: POST_NOTIFICATIONS not granted")
                    requestNotificationPermissionIfNeeded()
                    return
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val existing = manager.getNotificationChannel(channelId)
                if (existing == null) {
                    val channel = android.app.NotificationChannel(
                        channelId,
                        "FONEX Commands",
                        android.app.NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Notifications for FONEX device commands"
                        enableVibration(true)
                    }
                    manager.createNotificationChannel(channel)
                }
            }

            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            val pendingIntent = android.app.PendingIntent.getActivity(
                this, 0, launchIntent,
                android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
            )

            val notification = NotificationCompat.Builder(this, channelId)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .build()

            val notifId = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
            manager.notify(notifId, notification)
            Log.i(TAG, "Command notification shown: $title")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show command notification: ${e.message}", e)
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

    private fun applyWarningSystemWallpaper(refreshBackup: Boolean) {
        val now = System.currentTimeMillis()
        if (
            !refreshBackup &&
            isWarningWallpaperMarkedApplied() &&
            isCurrentWarningWallpaperVersionApplied() &&
            (now - getWarningWallpaperLastAppliedAt()) < WARNING_WALLPAPER_REAPPLY_COOLDOWN_MS
        ) {
            Log.i(TAG, "Skipping warning wallpaper reapply: already applied")
            return
        }
        try {
            ensureOriginalWallpaperBackup(forceRefresh = refreshBackup)
            val base = loadOriginalWallpaperBitmap() ?: loadCurrentWallpaperBitmap() ?: run {
                Log.w(TAG, "No readable wallpaper source; using generated fallback base")
                createFallbackWallpaperBaseBitmap()
            }
            val warningBitmap = drawWarningBanner(base)
            setSystemWallpaper(warningBitmap)
            markWarningWallpaperApplied()
            Log.i(TAG, "Warning system wallpaper applied")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply warning wallpaper: ${e.message}", e)
        }
    }

    private fun restoreOriginalSystemWallpaper() {
        try {
            val original = loadOriginalWallpaperBitmap() ?: run {
                Log.i(TAG, "No original wallpaper backup found; skipping restore")
                setWarningWallpaperMarkedApplied(false)
                return
            }
            setSystemWallpaper(original)
            setWarningWallpaperMarkedApplied(false)
            Log.i(TAG, "Original system wallpaper restored")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restore original wallpaper: ${e.message}", e)
        }
    }

    private fun ensureOriginalWallpaperBackup(forceRefresh: Boolean) {
        val backupFile = File(filesDir, ORIGINAL_WALLPAPER_FILE)
        if (backupFile.exists() && !forceRefresh) return

        val current = loadCurrentWallpaperBitmap() ?: return
        try {
            FileOutputStream(backupFile).use { out ->
                current.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
            Log.i(TAG, "Original wallpaper backup created")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create wallpaper backup: ${e.message}", e)
        }
    }

    private fun loadCurrentWallpaperBitmap(): Bitmap? {
        return try {
            val drawable = WallpaperManager.getInstance(applicationContext).drawable ?: return null
            when (drawable) {
                is BitmapDrawable -> drawable.bitmap.copy(Bitmap.Config.ARGB_8888, true)
                else -> {
                    val width = drawable.intrinsicWidth.takeIf { it > 0 } ?: 1080
                    val height = drawable.intrinsicHeight.takeIf { it > 0 } ?: 1920
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bitmap)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                    bitmap
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Unable to read current wallpaper: ${e.message}")
            null
        }
    }

    private fun loadOriginalWallpaperBitmap(): Bitmap? {
        val backupFile = File(filesDir, ORIGINAL_WALLPAPER_FILE)
        if (!backupFile.exists()) return null
        return BitmapFactory.decodeFile(backupFile.absolutePath)
    }

    private fun createFallbackWallpaperBaseBitmap(): Bitmap {
        val metrics = resources.displayMetrics
        val width = maxOf(metrics.widthPixels, 1080)
        val height = maxOf(metrics.heightPixels, 1920)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f,
                0f,
                0f,
                height.toFloat(),
                intArrayOf(
                    Color.argb(255, 10, 16, 28),
                    Color.argb(255, 24, 33, 53),
                    Color.argb(255, 11, 17, 30)
                ),
                null,
                Shader.TileMode.CLAMP
            )
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        return bitmap
    }

    private fun isPaidInFull(): Boolean {
        val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
        return prefs.getBoolean("is_paid_in_full", false)
    }

    private fun isWarningWallpaperMarkedApplied(): Boolean {
        val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_WARNING_WALLPAPER_APPLIED, false)
    }

    private fun setWarningWallpaperMarkedApplied(applied: Boolean) {
        val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
        prefs.edit().putBoolean(KEY_WARNING_WALLPAPER_APPLIED, applied).apply()
    }

    private fun getWarningWallpaperLastAppliedAt(): Long {
        val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
        return prefs.getLong(KEY_WARNING_WALLPAPER_LAST_APPLIED_AT, 0L)
    }

    private fun isCurrentWarningWallpaperVersionApplied(): Boolean {
        val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
        return prefs.getInt(KEY_WARNING_WALLPAPER_VERSION, 0) == WARNING_WALLPAPER_VERSION
    }

    private fun markWarningWallpaperApplied() {
        val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_WARNING_WALLPAPER_APPLIED, true)
            .putInt(KEY_WARNING_WALLPAPER_VERSION, WARNING_WALLPAPER_VERSION)
            .putLong(KEY_WARNING_WALLPAPER_LAST_APPLIED_AT, System.currentTimeMillis())
            .apply()
    }

    private fun refreshHomeWarningWidget() {
        try {
            FonexWarningWidgetProvider.updateAll(applicationContext)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to refresh due widget: ${e.message}")
        }
    }

    private fun requestPinWarningWidgetIfSupported() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
            if (!appWidgetManager.isRequestPinAppWidgetSupported) return

            val provider = ComponentName(applicationContext, FonexWarningWidgetProvider::class.java)
            val existing = appWidgetManager.getAppWidgetIds(provider)
            if (existing.isNotEmpty()) return

            val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", Context.MODE_PRIVATE)
            if (prefs.getBoolean(KEY_WIDGET_PIN_REQUESTED, false)) return

            val requested = appWidgetManager.requestPinAppWidget(provider, null, null)
            if (requested) {
                prefs.edit().putBoolean(KEY_WIDGET_PIN_REQUESTED, true).apply()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to request due widget pin: ${e.message}")
        }
    }

    private fun drawWarningBanner(base: Bitmap): Bitmap {
        val bitmap = fitBitmapToScreen(base).copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(bitmap)

        val width = bitmap.width.toFloat()
        val height = bitmap.height.toFloat()
        canvas.drawColor(Color.WHITE)

        val margin = (width * 0.08f).coerceIn(28f, 84f)
        val contentWidth = width - (margin * 2)
        val centerX = width / 2f

        val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(255, 23, 62, 124)
        }
        canvas.drawRect(0f, 0f, width, (height * 0.02f).coerceAtLeast(14f), accentPaint)

        val logoSize = (width * 0.22f).coerceIn(96f, 220f)
        val logoTop = (height * 0.08f).coerceIn(48f, 160f)
        val logoRect = RectF(
            centerX - logoSize / 2f,
            logoTop,
            centerX + logoSize / 2f,
            logoTop + logoSize
        )
        val logoDrawable = BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
        if (logoDrawable != null && !logoDrawable.isRecycled) {
            val logoSrc = android.graphics.Rect(0, 0, logoDrawable.width, logoDrawable.height)
            canvas.drawBitmap(logoDrawable, logoSrc, logoRect, Paint(Paint.ANTI_ALIAS_FLAG))
        }

        val brandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(255, 27, 45, 74)
            textAlign = Paint.Align.CENTER
            textSize = (width * 0.052f).coerceIn(24f, 58f)
            typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
        }
        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(255, 198, 40, 40)
            textAlign = Paint.Align.CENTER
            textSize = (width * 0.061f).coerceIn(28f, 70f)
            typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
        }
        val enPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(255, 46, 66, 96)
            textAlign = Paint.Align.CENTER
            textSize = (width * 0.036f).coerceIn(18f, 38f)
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        }
        val bnPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(255, 46, 66, 96)
            textAlign = Paint.Align.CENTER
            textSize = (width * 0.034f).coerceIn(16f, 36f)
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        }
        val phonePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(255, 0, 121, 107)
            textAlign = Paint.Align.CENTER
            textSize = (width * 0.033f).coerceIn(16f, 34f)
            typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
        }

        fun fitCenterText(paint: Paint, text: String, minSize: Float) {
            while (paint.measureText(text) > contentWidth && paint.textSize > minSize) {
                paint.textSize -= 1f
            }
        }

        val brandText = "FONEX"
        val titleText = "THIS DEVICE AMOUNT IS PENDING"
        val enLine1 = "Please clear due amount to continue normal use."
        val bnLine1 = "এই ডিভাইসের কিস্তির টাকা বাকি আছে।"
        val bnLine2a = "স্বাভাবিকভাবে ব্যবহার করতে"
        val bnLine2b = "বকেয়া দ্রুত পরিশোধ করুন।"
        val phoneLine1 = "Support: $SUPPORT_PHONE_1"
        val phoneLine2 = "Support: $SUPPORT_PHONE_2"
        val poweredBy = "Powered by $SUPPORT_STORE_NAME"

        fitCenterText(titlePaint, titleText, 16f)
        fitCenterText(enPaint, enLine1, 14f)
        fitCenterText(bnPaint, bnLine1, 14f)
        fitCenterText(bnPaint, bnLine2a, 14f)
        fitCenterText(bnPaint, bnLine2b, 14f)
        fitCenterText(phonePaint, phoneLine1, 12f)
        fitCenterText(phonePaint, phoneLine2, 12f)

        var y = logoRect.bottom + (height * 0.065f).coerceIn(24f, 70f)
        canvas.drawText(brandText, centerX, y, brandPaint)

        y += (height * 0.075f).coerceIn(34f, 86f)
        canvas.drawText(titleText, centerX, y, titlePaint)

        y += (height * 0.07f).coerceIn(30f, 76f)
        canvas.drawText(enLine1, centerX, y, enPaint)

        y += (height * 0.056f).coerceIn(24f, 62f)
        canvas.drawText(bnLine1, centerX, y, bnPaint)

        y += (height * 0.045f).coerceIn(20f, 48f)
        canvas.drawText(bnLine2a, centerX, y, bnPaint)

        y += (height * 0.045f).coerceIn(20f, 48f)
        canvas.drawText(bnLine2b, centerX, y, bnPaint)

        y += (height * 0.08f).coerceIn(34f, 88f)
        canvas.drawText(phoneLine1, centerX, y, phonePaint)

        y += (height * 0.05f).coerceIn(20f, 56f)
        canvas.drawText(phoneLine2, centerX, y, phonePaint)

        y += (height * 0.075f).coerceIn(30f, 80f)
        canvas.drawText(poweredBy, centerX, y, enPaint)

        return bitmap
    }

    private fun setSystemWallpaper(bitmap: Bitmap) {
        val wallpaperManager = WallpaperManager.getInstance(applicationContext)
        val wallpaperBitmap = fitBitmapToScreen(bitmap)
        val (screenWidth, screenHeight) = getScreenWallpaperSize()
        try {
            wallpaperManager.suggestDesiredDimensions(screenWidth, screenHeight)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set desired wallpaper dimensions: ${e.message}")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            wallpaperManager.setBitmap(wallpaperBitmap, null, true, WallpaperManager.FLAG_SYSTEM)
        } else {
            wallpaperManager.setBitmap(wallpaperBitmap)
        }
    }

    private fun getScreenWallpaperSize(): Pair<Int, Int> {
        val metrics = resources.displayMetrics
        val width = max(metrics.widthPixels, 1080)
        val height = max(metrics.heightPixels, 1920)
        return width to height
    }

    private fun fitBitmapToScreen(source: Bitmap): Bitmap {
        val (targetWidth, targetHeight) = getScreenWallpaperSize()
        if (source.width == targetWidth && source.height == targetHeight) {
            return source
        }

        val scale = max(
            targetWidth.toFloat() / source.width.toFloat(),
            targetHeight.toFloat() / source.height.toFloat()
        )
        val scaledWidth = source.width * scale
        val scaledHeight = source.height * scale
        val left = (targetWidth - scaledWidth) / 2f
        val top = (targetHeight - scaledHeight) / 2f

        val output = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            isFilterBitmap = true
        }
        canvas.drawBitmap(
            source,
            null,
            RectF(left, top, left + scaledWidth, top + scaledHeight),
            paint
        )
        return output
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

    private fun openAddAccountSettings(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_ADD_ACCOUNT),
            Intent(Settings.ACTION_SYNC_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Try next fallback.
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
