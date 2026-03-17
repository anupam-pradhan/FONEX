package com.roycommunication.fonex

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.Base64
import java.util.Timer
import java.util.TimerTask
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Foreground keep-alive service to reduce OEM background process kills.
 * Also runs a lightweight legacy check-in fallback so lock/unlock actions
 * can still be applied when Flutter realtime is not active.
 */
class KeepAliveService : Service() {

    companion object {
        private const val TAG = "FonexKeepAliveService"
        private const val CHANNEL_ID = "fonex_keepalive_channel"
        private const val CHANNEL_NAME = "FONEX Protection"
        private const val NOTIFICATION_ID = 2207
        private const val PREFS_DEVICE = "fonex_device_prefs"
        private const val PREFS_FLUTTER = "FlutterSharedPreferences"
        private const val KEY_PAID_IN_FULL = "is_paid_in_full"
        private const val KEY_LAST_UNLOCK_MS = "last_unlock_ms"
        private const val KEY_DEVICE_HASH_STORED = "device_hash_stored"
        private const val KEY_REALTIME_DEVICE_ID = "realtime_device_id"
        private const val EXTRA_BACKGROUND_LOCK_ACTION = "fonex_background_lock_action"
        private const val EXTRA_BACKGROUND_UNLOCK_ACTION = "fonex_background_unlock_action"
        private val SERVER_BASE_URL = BuildConfig.SERVER_BASE_URL
        private const val CHECKIN_PATH = "/checkin"
        private const val CHECKIN_INITIAL_DELAY_MS = 25_000L
        private const val CHECKIN_INTERVAL_MS = 2 * 60_000L
        private const val KEY_SIGNED_COMMAND_SEEN = "signed_command_seen_ids"
        private const val MAX_SEEN_COMMAND_IDS = 300
        private const val FUTURE_SKEW_SECONDS = 60L

        fun start(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }
    }

    private var checkInTimer: Timer? = null
    private val checkInInFlight = AtomicBoolean(false)
    private data class DeviceIdentifiers(
        val deviceHash: String,
        val deviceId: String,
    )

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildNotification())
        reEnforcePolicies()
        scheduleLegacyCheckInFallback()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        reEnforcePolicies()
        triggerLegacyCheckIn()
        return START_STICKY
    }

    override fun onDestroy() {
        checkInTimer?.cancel()
        checkInTimer = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        createNotificationChannel()
        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
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
            val prefs = applicationContext.getSharedPreferences(PREFS_DEVICE, Context.MODE_PRIVATE)
            val isPaidInFull = prefs.getBoolean(KEY_PAID_IN_FULL, false)
            manager.enforceFactoryResetBlock()
            manager.enforceHomeLauncherForCurrentState()
            Log.i(TAG, "Policies re-enforced from keep-alive service. paidInFull=$isPaidInFull")
        } catch (e: Exception) {
            Log.w(TAG, "Policy re-enforcement failed: ${e.message}")
        }
    }

    private fun scheduleLegacyCheckInFallback() {
        checkInTimer?.cancel()
        checkInTimer = Timer("fonex-legacy-checkin", true).apply {
            scheduleAtFixedRate(
                object : TimerTask() {
                    override fun run() {
                        triggerLegacyCheckIn()
                    }
                },
                CHECKIN_INITIAL_DELAY_MS,
                CHECKIN_INTERVAL_MS,
            )
        }
    }

    private fun triggerLegacyCheckIn() {
        if (!checkInInFlight.compareAndSet(false, true)) return
        Thread {
            try {
                performLegacyCheckIn()
            } finally {
                checkInInFlight.set(false)
            }
        }.start()
    }

    private fun performLegacyCheckIn() {
        val manager = DeviceLockManager(applicationContext)
        if (!manager.isDeviceOwner()) return

        val identifiers = resolveDeviceIdentifiers() ?: run {
            Log.w(TAG, "Legacy check-in skipped: missing local device hash/id")
            return
        }

        val imei = resolveImei()
        val payload = JSONObject().apply {
            put("device_hash", identifiers.deviceHash)
            put("device_id", identifiers.deviceId)
            put("imei", imei)
            put("is_locked", manager.isDeviceLocked())
            put("last_seen", java.time.Instant.now().toString())
            put("timestamp", java.time.Instant.now().toString())
        }
        Log.i(
            TAG,
            "Legacy check-in payload identifiers: hash=${identifiers.deviceHash} id=${identifiers.deviceId}",
        )

        val endpoint = "$SERVER_BASE_URL$CHECKIN_PATH"
        val (statusCode, body) = postJson(endpoint, payload.toString()) ?: return
        Log.i(TAG, "Legacy check-in response: status=$statusCode body=$body")
        if (statusCode !in 200..299 || body.isBlank()) return

        val response = try {
            JSONObject(body)
        } catch (e: Exception) {
            Log.w(TAG, "Legacy check-in parse failed: ${e.message}")
            return
        }

        applyPaidStateFromServer(response, manager)
        val action = response.optString("action", "none").trim().lowercase()
        when (action) {
            "lock" -> {
                if (!isSignedActionAuthorized(response, "LOCK", identifiers)) {
                    Log.w(TAG, "Rejected fallback LOCK action: failed command authorization")
                    return
                }
                handleLockActionFromFallback(manager)
            }
            "unlock" -> {
                if (!isSignedActionAuthorized(response, "UNLOCK", identifiers)) {
                    Log.w(TAG, "Rejected fallback UNLOCK action: failed command authorization")
                    return
                }
                handleUnlockActionFromFallback(manager)
            }
            else -> Unit
        }
    }

    private fun applyPaidStateFromServer(response: JSONObject, manager: DeviceLockManager) {
        val paymentStatus = response.optString("payment_status", "").trim().lowercase()
        val paidByStatus = paymentStatus in setOf(
            "paid",
            "paid_in_full",
            "full_paid",
            "completed",
            "settled",
        )
        val paid = response.optBoolean("is_paid_in_full", false) ||
            response.optBoolean("paid_in_full", false) ||
            paidByStatus

        val prefs = applicationContext.getSharedPreferences(PREFS_DEVICE, Context.MODE_PRIVATE)
        val currentPaid = prefs.getBoolean(KEY_PAID_IN_FULL, false)
        if (paid != currentPaid) {
            prefs.edit().putBoolean(KEY_PAID_IN_FULL, paid).apply()
            if (paid) {
                manager.enforcePaidInFullState(activity = null)
            } else {
                manager.enforceFactoryResetBlock()
            }
            Log.i(TAG, "Legacy check-in paid state synced: paidInFull=$paid")
        }
    }

    private fun handleLockActionFromFallback(manager: DeviceLockManager) {
        val prefs = applicationContext.getSharedPreferences(PREFS_DEVICE, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_PAID_IN_FULL, false)) {
            Log.i(TAG, "Ignoring fallback lock action: device marked paid in full")
            return
        }
        if (manager.isDeviceLocked()) return

        manager.setDeviceLockedFlag(true)
        manager.enforceFactoryResetBlock()
        manager.enforceHomeLauncher(unpaidMode = true)
        manager.lockScreenNow()
        launchAppForImmediateLockUi()
        Log.i(TAG, "Fallback lock action applied in keep-alive service")
    }

    private fun handleUnlockActionFromFallback(manager: DeviceLockManager) {
        val prefs = applicationContext.getSharedPreferences(PREFS_DEVICE, Context.MODE_PRIVATE)
        val wasLocked = manager.isDeviceLocked()
        if (!wasLocked) return

        manager.setDeviceLockedFlag(false)
        prefs.edit().putLong(KEY_LAST_UNLOCK_MS, System.currentTimeMillis()).apply()
        manager.enforceHomeLauncher(unpaidMode = false)
        launchAppForUnlockCleanup()
        Log.i(TAG, "Fallback unlock action applied in keep-alive service")
    }

    private fun isSignedActionAuthorized(
        response: JSONObject,
        action: String,
        identifiers: DeviceIdentifiers,
    ): Boolean {
        val commandId = response.optString("command_id").trim().ifEmpty {
            response.optString("id").trim()
        }
        if (commandId.isNotEmpty() && isReplayCommandId(commandId)) {
            Log.w(TAG, "Rejected signed action replay: commandId=$commandId action=$action")
            return false
        }

        val enforceSigned = BuildConfig.ENFORCE_SIGNED_COMMANDS
        val signature = response.optString("command_signature").trim().ifEmpty {
            response.optString("signature").trim()
        }
        if (!enforceSigned && signature.isEmpty()) {
            if (commandId.isNotEmpty()) {
                markCommandIdSeen(commandId)
            }
            return true
        }

        val secret = BuildConfig.COMMAND_SIGNING_SECRET.trim()
        if (secret.isEmpty()) {
            Log.w(TAG, "Signed command rejected: COMMAND_SIGNING_SECRET is empty")
            return false
        }
        if (signature.isEmpty() || commandId.isEmpty()) {
            Log.w(TAG, "Signed command rejected: missing signature or command_id")
            return false
        }

        val issuedAtSeconds = parseEpochSeconds(
            response.opt("command_ts")
                ?: response.opt("issued_at")
                ?: response.opt("timestamp")
                ?: response.opt("created_at")
        ) ?: run {
            Log.w(TAG, "Signed command rejected: missing/invalid command timestamp")
            return false
        }

        val targetDevice = response.optString("device_id").trim().ifEmpty {
            response.optString("device_hash").trim()
        }
        if (targetDevice.isNotEmpty() && targetDevice != identifiers.deviceId) {
            Log.w(
                TAG,
                "Signed command rejected: target mismatch target=$targetDevice local=${identifiers.deviceId}",
            )
            return false
        }
        val effectiveTarget = if (targetDevice.isNotEmpty()) targetDevice else identifiers.deviceId
        val nowSeconds = System.currentTimeMillis() / 1000
        val ageSeconds = nowSeconds - issuedAtSeconds
        if (
            ageSeconds < -FUTURE_SKEW_SECONDS ||
            ageSeconds > BuildConfig.COMMAND_SIGNATURE_MAX_AGE_SECONDS.toLong()
        ) {
            Log.w(
                TAG,
                "Signed command rejected: timestamp out of range ageSeconds=$ageSeconds",
            )
            return false
        }

        val nonce = response.optString("command_nonce").trim().ifEmpty {
            response.optString("nonce").trim()
        }
        val canonical = "$commandId|$action|$effectiveTarget|$issuedAtSeconds|$nonce"
        if (!isSignatureMatch(secret = secret, canonical = canonical, received = signature)) {
            Log.w(TAG, "Signed command rejected: signature mismatch")
            return false
        }

        markCommandIdSeen(commandId)
        return true
    }

    private fun parseEpochSeconds(value: Any?): Long? {
        if (value == null) return null
        return when (value) {
            is Number -> {
                val raw = value.toLong()
                if (raw > 1_000_000_000_000L) raw / 1000L else raw
            }
            is String -> {
                val trimmed = value.trim()
                if (trimmed.isEmpty()) return null
                val intValue = trimmed.toLongOrNull()
                if (intValue != null) {
                    if (intValue > 1_000_000_000_000L) intValue / 1000L else intValue
                } else {
                    try {
                        Instant.parse(trimmed).epochSecond
                    } catch (_: Exception) {
                        null
                    }
                }
            }
            else -> null
        }
    }

    private fun isSignatureMatch(secret: String, canonical: String, received: String): Boolean {
        val mac = Mac.getInstance("HmacSHA256")
        val keySpec = SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA256")
        mac.init(keySpec)
        val digest = mac.doFinal(canonical.toByteArray(Charsets.UTF_8))

        val expectedHex = digest.joinToString("") { "%02x".format(it) }
        val expectedBase64 = Base64.getEncoder().encodeToString(digest)
        val expectedBase64Url = Base64.getUrlEncoder().withoutPadding().encodeToString(digest)

        val normalizedReceived = received.trim()
        return constantTimeEquals(normalizedReceived.lowercase(), expectedHex) ||
            constantTimeEquals(normalizedReceived, expectedBase64) ||
            constantTimeEquals(normalizedReceived.replace("=", ""), expectedBase64Url)
    }

    private fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var diff = 0
        for (i in a.indices) {
            diff = diff or (a[i].code xor b[i].code)
        }
        return diff == 0
    }

    private fun isReplayCommandId(commandId: String): Boolean {
        val prefs = applicationContext.getSharedPreferences(PREFS_DEVICE, Context.MODE_PRIVATE)
        val seen = prefs.getStringSet(KEY_SIGNED_COMMAND_SEEN, emptySet()) ?: emptySet()
        return seen.contains(commandId)
    }

    private fun markCommandIdSeen(commandId: String) {
        val prefs = applicationContext.getSharedPreferences(PREFS_DEVICE, Context.MODE_PRIVATE)
        val current = (prefs.getStringSet(KEY_SIGNED_COMMAND_SEEN, emptySet()) ?: emptySet())
            .toMutableList()
        if (current.contains(commandId)) return
        current.add(0, commandId)
        while (current.size > MAX_SEEN_COMMAND_IDS) {
            current.removeLast()
        }
        prefs.edit().putStringSet(KEY_SIGNED_COMMAND_SEEN, current.toSet()).apply()
    }

    private fun launchAppForImmediateLockUi() {
        try {
            val launchIntent =
                packageManager.getLaunchIntentForPackage(packageName)
                    ?: Intent(this, MainActivity::class.java)
            launchIntent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            launchIntent.putExtra(EXTRA_BACKGROUND_LOCK_ACTION, true)
            startActivity(launchIntent)
        } catch (e: Exception) {
            Log.w(TAG, "Could not launch app for fallback lock: ${e.message}")
        }
    }

    private fun launchAppForUnlockCleanup() {
        try {
            val launchIntent =
                packageManager.getLaunchIntentForPackage(packageName)
                    ?: Intent(this, MainActivity::class.java)
            launchIntent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            launchIntent.putExtra(EXTRA_BACKGROUND_UNLOCK_ACTION, true)
            startActivity(launchIntent)
        } catch (e: Exception) {
            Log.w(TAG, "Could not launch app for fallback unlock cleanup: ${e.message}")
        }
    }

    private fun resolveDeviceIdentifiers(): DeviceIdentifiers? {
        val nativePrefs = applicationContext.getSharedPreferences(PREFS_DEVICE, Context.MODE_PRIVATE)
        val flutterPrefs = applicationContext.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val hashCandidates = listOf(
            nativePrefs.getString(KEY_DEVICE_HASH_STORED, null),
            flutterPrefs.getString("flutter.device_hash_stored", null),
            flutterPrefs.getString("flutter.device_hash_stable", null),
            flutterPrefs.getString("device_hash_stored", null),
            flutterPrefs.getString("device_hash_stable", null),
        )
        val deviceHash = hashCandidates
            .mapNotNull { it?.trim() }
            .firstOrNull { it.isNotEmpty() }
            ?: return null

        val idCandidates = listOf(
            nativePrefs.getString(KEY_REALTIME_DEVICE_ID, null),
            flutterPrefs.getString("flutter.realtime_device_id", null),
            flutterPrefs.getString("flutter.device_id", null),
            flutterPrefs.getString("realtime_device_id", null),
            flutterPrefs.getString("device_id", null),
        )
        val deviceId = idCandidates
            .mapNotNull { it?.trim() }
            .firstOrNull { it.isNotEmpty() }
            ?: deviceHash

        return DeviceIdentifiers(deviceHash = deviceHash, deviceId = deviceId)
    }

    private fun resolveImei(): String {
        return try {
            val granted = ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_PHONE_STATE,
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (!granted) return "Not Found"

            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                tm.imei ?: "Not Found"
            } else {
                @Suppress("DEPRECATION")
                tm.deviceId ?: "Not Found"
            }
        } catch (_: Exception) {
            "Not Found"
        }
    }

    private fun postJson(endpoint: String, jsonBody: String): Pair<Int, String>? {
        var connection: HttpURLConnection? = null
        return try {
            val url = URL(endpoint)
            connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8_000
                readTimeout = 8_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("User-Agent", "FONEX-KeepAlive/1.0")
            }

            OutputStreamWriter(connection.outputStream).use { writer ->
                writer.write(jsonBody)
                writer.flush()
            }

            val status = connection.responseCode
            val stream = if (status in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream
            }
            val body = if (stream != null) {
                BufferedReader(InputStreamReader(stream)).use { it.readText() }
            } else {
                ""
            }
            status to body
        } catch (e: Exception) {
            Log.w(TAG, "Legacy check-in request failed: ${e.message}")
            null
        } finally {
            connection?.disconnect()
        }
    }
}
