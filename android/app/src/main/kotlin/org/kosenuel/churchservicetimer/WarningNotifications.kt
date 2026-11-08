package org.kosenuel.churchservicetimer

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings

/** System alarms keep operator warnings independent of Flutter frame callbacks. */
object WarningNotifications {
    // v2 adds a distinct vibration that watches mirror; channels are immutable.
    private const val CHANNEL = "service_warnings_v2"
    private const val OLD_CHANNEL = "service_warnings_v1"
    private val VIBRATION = longArrayOf(0, 400, 200, 400, 200, 800)
    private const val NOTICE = 4301
    private const val CLEAR = "clear-warning"
    private fun prefs(c: Context) = c.getSharedPreferences("warning-delivery", Context.MODE_PRIVATE)
    private fun manager(c: Context) = c.getSystemService(NotificationManager::class.java)
    private fun alarms(c: Context) = c.getSystemService(AlarmManager::class.java)

    fun ensureChannel(c: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL, "Service timing warnings", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Automatic countdown warnings for the service operator"
            channel.setSound(Settings.System.DEFAULT_NOTIFICATION_URI,
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
            channel.enableVibration(true)
            channel.vibrationPattern = VIBRATION
            manager(c).createNotificationChannel(channel)
            manager(c).deleteNotificationChannel(OLD_CHANNEL)
        }
    }

    fun status(c: Context): Map<String, Boolean> {
        ensureChannel(c)
        val allowed = Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val channel = if (Build.VERSION.SDK_INT >= 26) manager(c).getNotificationChannel(CHANNEL) else null
        return mapOf(
            "enabled" to (allowed && manager(c).areNotificationsEnabled() && (channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE)),
            "sound" to (channel == null || channel.sound != null),
            "exact" to (Build.VERSION.SDK_INT < 31 || alarms(c).canScheduleExactAlarms())
        )
    }

    private fun pending(c: Context, id: String, title: String = "", body: String = ""): PendingIntent {
        val intent = Intent(c, WarningReceiver::class.java)
            .setData(Uri.parse("churchservicetimer://warning/${Uri.encode(id)}"))
            .putExtra("id", id).putExtra("title", title).putExtra("body", body)
        return PendingIntent.getBroadcast(c, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun sync(c: Context, plan: Map<*, *>) {
        ensureChannel(c)
        val settings = prefs(c)
        val previous = settings.getStringSet("active", emptySet())!!.toSet()
        val session = plan["session"] as String
        val entries = (plan["alarms"] as? List<*>)?.map { it as Map<*, *> } ?: emptyList()
        val ids = entries.map { it["id"] as String }.toSet()
        val edit = settings.edit().putStringSet("active", ids).putString("session", session)
        val scope = plan["scope"] as? String ?: session
        val clearSeconds = (plan["clearSeconds"] as? Number)?.toInt() ?: 30
        check(clearSeconds in setOf(0, 15, 30, 60))
        edit.putInt("clearSeconds", clearSeconds).putString("scope", scope)
        if (settings.getString("scope", null) != scope) manager(c).cancel(NOTICE)
        if (settings.getString("session", null) != session) {
            edit.putStringSet("delivered", emptySet())
            manager(c).cancel(NOTICE)
        }
        check(edit.commit()) { "Cannot save warning schedule" }
        previous.forEach { alarms(c).cancel(pending(c, it)) }
        if (status(c)["enabled"] != true) return
        val notice = plan["notice"] as? Map<*, *>
        if (notice != null) deliver(c, notice["id"] as String, notice["title"] as String, notice["body"] as String, false)
        val delivered = settings.getStringSet("delivered", emptySet())!!
        for (entry in entries) {
            val id = entry["id"] as String
            if (id in delivered) continue
            val at = (entry["at"] as Number).toLong().coerceAtLeast(SystemClock.elapsedRealtime() + 1)
            val intent = pending(c, id, entry["title"] as String, entry["body"] as String)
            if (Build.VERSION.SDK_INT < 31 || alarms(c).canScheduleExactAlarms()) {
                try { alarms(c).setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, intent) }
                catch (_: SecurityException) { alarms(c).setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, intent) }
            } else alarms(c).setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, intent)
        }
    }

    fun deliver(c: Context, id: String, title: String, body: String, requireActive: Boolean = true) {
        val settings = prefs(c)
        if (requireActive && id !in settings.getStringSet("active", emptySet())!!) return
        val delivered = settings.getStringSet("delivered", emptySet())!!.toMutableSet()
        if (id in delivered || status(c)["enabled"] != true) return
        post(c, title, body)
        delivered.add(id)
        check(settings.edit().putStringSet("delivered", delivered).commit()) { "Cannot save notification delivery" }
    }

    @Suppress("DEPRECATION")
    private fun post(c: Context, title: String, body: String) {
        val launch = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
        builder.setSmallIcon(R.drawable.ic_warning_notification).setContentTitle(title).setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body)).setContentIntent(launch)
            .setAutoCancel(true).setCategory(Notification.CATEGORY_REMINDER).setPriority(Notification.PRIORITY_HIGH)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
        if (Build.VERSION.SDK_INT < 26) builder.setSound(Settings.System.DEFAULT_NOTIFICATION_URI).setVibrate(VIBRATION)
        val seconds = prefs(c).getInt("clearSeconds", 30)
        if (Build.VERSION.SDK_INT >= 26 && seconds > 0) builder.setTimeoutAfter(seconds * 1000L)
        // API 24/25 fallback is keyed to this exact post; an old expiry cannot clear a newer warning.
        val token = java.util.UUID.randomUUID().toString()
        prefs(c).edit().putString("noticeToken", token).apply()
        if (Build.VERSION.SDK_INT < 26 && seconds > 0) {
            val expiry = Intent(c, WarningReceiver::class.java).setAction(CLEAR).putExtra("token", token)
            val pending = PendingIntent.getBroadcast(c, NOTICE, expiry, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            alarms(c).setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + seconds * 1000L, pending)
        }
        manager(c).notify(NOTICE, builder.build())
    }

    fun clearExpired(c: Context, intent: Intent): Boolean {
        if (intent.action != CLEAR) return false
        if (intent.getStringExtra("token") == prefs(c).getString("noticeToken", null)) manager(c).cancel(NOTICE)
        return true
    }

    fun test(c: Context) {
        check(status(c)["enabled"] == true) { "Enable phone notifications first." }
        post(c, "Church Service Timer test warning", "Notification sound follows your phone volume, channel sound and Do Not Disturb settings.")
    }
}

class WarningReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (WarningNotifications.clearExpired(context, intent)) return
        val id = intent.getStringExtra("id") ?: return
        try {
            WarningNotifications.deliver(context, id, intent.getStringExtra("title") ?: "Service warning", intent.getStringExtra("body") ?: "")
        } catch (_: Exception) { /* Permission/settings may change after scheduling. */ }
    }
}
