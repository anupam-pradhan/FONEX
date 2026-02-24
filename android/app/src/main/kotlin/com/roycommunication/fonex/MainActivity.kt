package com.roycommunication.fonex

import android.app.WallpaperManager
import android.os.Bundle
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.Context
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
        val paidInFull = isPaidInFull()

        // Ensure reset/uninstall protection persists across app restarts.
        if (deviceLockManager.isDeviceOwner()) {
            deviceLockManager.enforceFactoryResetBlock()

            // If device was locked before (e.g., after reboot), re-engage lock task
            if (deviceLockManager.isDeviceLocked()) {
                Log.i(TAG, "Device locked state detected — re-engaging lock")
                deviceLockManager.enableDeviceLock(this)
            }
        }

        if (!paidInFull) {
            // Show EMI warning wallpaper for unpaid devices.
            applyWarningSystemWallpaper(refreshBackup = false)
        } else {
            restoreOriginalSystemWallpaper()
        }
    }

    override fun onResume() {
        super.onResume()
        if (deviceLockManager.isDeviceOwner()) {
            // Re-apply unpaid protections and account-login allowance on every resume.
            deviceLockManager.enforceFactoryResetBlock()
        }
        if (isPaidInFull()) {
            restoreOriginalSystemWallpaper()
        } else {
            // Ensure warning wallpaper stays visible for unpaid devices.
            applyWarningSystemWallpaper(refreshBackup = false)
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

                "showResetBlockedMessage" -> {
                    android.widget.Toast.makeText(
                        this,
                        "⛔ Cannot reset this device — Please complete your EMI payment first. " +
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
                    if (paid) {
                        // Remove lock mode and restrictions once payment is fully completed.
                        deviceLockManager.disableDeviceLock(this)
                        deviceLockManager.setDeviceLockedFlag(false)
                        restoreOriginalSystemWallpaper()
                        releaseWakeLock()
                        deviceLockManager.enforceFactoryResetBlock() // This will remove the restriction
                        val ownerCleared = deviceLockManager.clearDeviceOwner()
                        Log.i(TAG, "Paid-in-full mode enabled. clearDeviceOwner=$ownerCleared")
                    } else {
                        // Re-enforce restrictions if payment status changes
                        deviceLockManager.enforceFactoryResetBlock()
                        applyWarningSystemWallpaper(refreshBackup = false)
                    }
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

                else -> {
                    result.notImplemented()
                }
            }
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
        try {
            ensureOriginalWallpaperBackup(forceRefresh = refreshBackup)
            val base = loadOriginalWallpaperBitmap() ?: loadCurrentWallpaperBitmap() ?: run {
                Log.w(TAG, "No readable wallpaper source; keeping existing wallpaper unchanged")
                return
            }
            val warningBitmap = drawWarningBanner(base)
            setSystemWallpaper(warningBitmap)
            Log.i(TAG, "Warning system wallpaper applied")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply warning wallpaper: ${e.message}", e)
        }
    }

    private fun restoreOriginalSystemWallpaper() {
        try {
            val original = loadOriginalWallpaperBitmap() ?: run {
                Log.i(TAG, "No original wallpaper backup found; skipping restore")
                return
            }
            setSystemWallpaper(original)
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

    private fun drawWarningBanner(base: Bitmap): Bitmap {
        val bitmap = base.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(bitmap)

        val width = bitmap.width.toFloat()
        val height = bitmap.height.toFloat()
        val margin = (width * 0.04f).coerceIn(20f, 56f)
        val cardHeight = (height * 0.2f).coerceIn(220f, 360f)
        val cardLeft = margin
        val cardTop = height - cardHeight - margin
        val cardRight = width - margin
        val cardBottom = height - margin
        val cardRadius = (cardHeight * 0.13f).coerceIn(18f, 34f)
        val cardRect = RectF(cardLeft, cardTop, cardRight, cardBottom)

        val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                cardLeft,
                cardTop,
                cardLeft,
                cardBottom,
                intArrayOf(
                    Color.argb(162, 8, 16, 29),
                    Color.argb(148, 10, 20, 35)
                ),
                null,
                Shader.TileMode.CLAMP
            )
        }
        val cardBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = (width * 0.0026f).coerceIn(1.6f, 3.2f)
            color = Color.argb(175, 225, 235, 248)
        }
        canvas.drawRoundRect(cardRect, cardRadius, cardRadius, cardPaint)
        canvas.drawRoundRect(cardRect, cardRadius, cardRadius, cardBorderPaint)

        val padding = (width * 0.03f).coerceIn(16f, 34f)
        val logoRadius = (cardHeight * 0.18f).coerceIn(24f, 40f)
        val logoCenterX = cardLeft + padding + logoRadius
        val logoCenterY = cardTop + cardHeight / 2f

        val logoShadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(105, 0, 0, 0)
        }
        val logoBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(244, 255, 255, 255)
        }
        val logoBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(225, 74, 133, 226)
            style = Paint.Style.STROKE
            strokeWidth = 2.5f
        }
        val logoOuterRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(130, 235, 243, 255)
            style = Paint.Style.STROKE
            strokeWidth = 2f
        }
        val logoTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(255, 40, 96, 205)
            textSize = (logoRadius * 1.05f).coerceAtLeast(24f)
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
        }
        val logoDrawable = BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
        val logoDrawRadius = logoRadius - 4f
        val logoLeft = logoCenterX - logoDrawRadius
        val logoTop = logoCenterY - logoDrawRadius
        val logoRight = logoCenterX + logoDrawRadius
        val logoBottom = logoCenterY + logoDrawRadius

        canvas.drawCircle(logoCenterX + 1.5f, logoCenterY + 2f, logoRadius + 1.5f, logoShadowPaint)
        canvas.drawCircle(logoCenterX, logoCenterY, logoRadius, logoBgPaint)
        canvas.drawCircle(logoCenterX, logoCenterY, logoRadius, logoBorderPaint)
        canvas.drawCircle(logoCenterX, logoCenterY, logoRadius + 4f, logoOuterRingPaint)

        if (logoDrawable != null && !logoDrawable.isRecycled) {
            val logoSrc = android.graphics.Rect(0, 0, logoDrawable.width, logoDrawable.height)
            val logoDst = RectF(logoLeft, logoTop, logoRight, logoBottom)
            canvas.drawBitmap(logoDrawable, logoSrc, logoDst, Paint(Paint.ANTI_ALIAS_FLAG))
        } else {
            val logoTextY = logoCenterY - (logoTextPaint.descent() + logoTextPaint.ascent()) / 2f
            canvas.drawText("F", logoCenterX, logoTextY, logoTextPaint)
        }

        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = (width * 0.037f).coerceIn(24f, 38f)
            typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
            setShadowLayer(3f, 0f, 1f, Color.argb(120, 0, 0, 0))
        }
        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(245, 235, 241, 252)
            textSize = (width * 0.024f).coerceIn(17f, 26f)
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        }

        val textStartX = logoCenterX + logoRadius + padding
        val textEndX = cardRight - padding
        val textMaxWidth = textEndX - textStartX

        fun fitText(paint: Paint, text: String, minSize: Float) {
            while (paint.measureText(text) > textMaxWidth && paint.textSize > minSize) {
                paint.textSize -= 1f
            }
        }

        val brandLine = "FONEX"
        val titleLine = "EMI PAYMENT PENDING"
        val infoLine = "This device has pending payment."
        val phoneLine1 = "Phone: $SUPPORT_PHONE_1"
        val phoneLine2 = "Phone: $SUPPORT_PHONE_2"

        fitText(titlePaint, titleLine, 18f)
        fitText(linePaint, infoLine, 14f)
        fitText(linePaint, phoneLine1, 14f)
        fitText(linePaint, phoneLine2, 14f)

        var y = cardTop + padding - linePaint.ascent()
        canvas.drawText(brandLine, textStartX, y, linePaint)
        y += (cardHeight * 0.2f).coerceIn(30f, 44f)
        canvas.drawText(titleLine, textStartX, y, titlePaint)
        y += (cardHeight * 0.18f).coerceIn(26f, 40f)
        canvas.drawText(infoLine, textStartX, y, linePaint)
        y += (cardHeight * 0.17f).coerceIn(24f, 36f)
        canvas.drawText(phoneLine1, textStartX, y, linePaint)
        y += (cardHeight * 0.16f).coerceIn(22f, 34f)
        canvas.drawText(phoneLine2, textStartX, y, linePaint)

        return bitmap
    }

    private fun setSystemWallpaper(bitmap: Bitmap) {
        val wallpaperManager = WallpaperManager.getInstance(applicationContext)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
        } else {
            wallpaperManager.setBitmap(bitmap)
        }
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
