package com.roycommunication.fonex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

class FonexWarningWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS_NAME = "fonex_device_prefs"
        private const val SUPPORT_PHONE_1 = "+91 8388855549"
        private const val SUPPORT_PHONE_2 = "+91 9635252455"

        fun updateAll(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, FonexWarningWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(component)
            appWidgetIds.forEach { appWidgetId ->
                updateWidget(context, appWidgetManager, appWidgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val isPaidInFull = prefs.getBoolean("is_paid_in_full", false)
            val views = RemoteViews(context.packageName, R.layout.fonex_warning_widget)

            if (isPaidInFull) {
                views.setTextViewText(R.id.emi_status_title, "PAYMENT CLEAR")
                views.setTextViewText(R.id.emi_status_subtitle, "This device has no pending EMI.")
                views.setTextViewText(R.id.emi_status_subtitle_bn, "এই ডিভাইসে কোনো বাকি কিস্তি নেই।")
                views.setTextViewText(R.id.emi_status_phone, "Fonex")
            } else {
                views.setTextViewText(R.id.emi_status_title, "EMI PAYMENT PENDING")
                views.setTextViewText(
                    R.id.emi_status_subtitle,
                    "This device has pending payment."
                )
                views.setTextViewText(
                    R.id.emi_status_subtitle_bn,
                    "এই ডিভাইসের কিস্তির টাকা বাকি আছে।"
                )
                views.setTextViewText(
                    R.id.emi_status_phone,
                    "Call: $SUPPORT_PHONE_1  |  $SUPPORT_PHONE_2"
                )
            }

            // Force marquee scrolling for long text lines.
            views.setBoolean(R.id.emi_status_title, "setSelected", true)
            views.setBoolean(R.id.emi_status_subtitle, "setSelected", true)
            views.setBoolean(R.id.emi_status_subtitle_bn, "setSelected", true)
            views.setBoolean(R.id.emi_status_phone, "setSelected", true)

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
                val pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, flags)
                views.setOnClickPendingIntent(R.id.fonex_widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }
}
