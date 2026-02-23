package com.roycommunication.fonex

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Watchdog worker that only verifies the keep-alive service is running.
 * It does not perform command polling.
 */
class KeepAliveWatchdogWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {

    companion object {
        private const val UNIQUE_WORK_NAME = "fonex_keepalive_watchdog"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<KeepAliveWatchdogWorker>(
                15,
                TimeUnit.MINUTES,
            ).build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }
    }

    override fun doWork(): Result {
        return try {
            KeepAliveService.start(applicationContext)
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }
}
