package org.kosenuel.cuekeeper

import android.app.*
import android.content.*
import android.os.*
import android.content.pm.ServiceInfo
import io.flutter.plugin.common.MethodChannel

/** Keeps the existing engine and authenticated display session alive. No restart
 * after process death: a fresh process must reconnect and review output. */
class ActiveService : Service() {
    companion object {
        @Volatile var running = false
        private val awaiting = mutableListOf<MethodChannel.Result>()
        fun start(context: Context, result: MethodChannel.Result) {
            if (running) { result.success(true); return }
            awaiting.add(result)
            try {
                val intent = Intent(context, ActiveService::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (e: Exception) { awaiting.remove(result); throw e }
        }
        fun stop(context: Context) { running = false; context.stopService(Intent(context, ActiveService::class.java)) }
    }
    private val handler = Handler(Looper.getMainLooper())
    private var wake: PowerManager.WakeLock? = null
    private var renewed = 0L
    private val pulse = object : Runnable {
        override fun run() {
            if (!running) return
            if (SystemClock.elapsedRealtime() - renewed >= 30000 || wake?.isHeld != true) {
                wake?.acquire(60000)
                renewed = SystemClock.elapsedRealtime()
            }
            MainActivity.bridge?.pulse()
            handler.postDelayed(this, 250)
        }
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            check(MainActivity.bridge != null) { "Open the app and reconnect the sign" }
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
                "active-service", "Active service timing", NotificationManager.IMPORTANCE_LOW))
            val open = PendingIntent.getActivity(this, 701, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "active-service") else Notification.Builder(this)
            val notification = builder.setSmallIcon(R.drawable.ic_warning_notification).setContentTitle("Church Service Timer is active")
                .setContentText("Display timing and warnings · tap to return")
                .setOngoing(true).setOnlyAlertOnce(true).setContentIntent(open).build()
            if (Build.VERSION.SDK_INT >= 29) startForeground(701, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            else startForeground(701, notification)
            if (!running) {
                wake = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ChurchServiceTimer:active")
                wake!!.setReferenceCounted(false)
                running = true
                handler.post(pulse)
            }
            awaiting.toList().also { awaiting.clear() }.forEach { it.success(true) }
        } catch (e: Exception) {
            awaiting.toList().also { awaiting.clear() }.forEach { it.error("SERVICE", e.message, null) }
            stopSelf()
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        running = false
        handler.removeCallbacks(pulse)
        if (wake?.isHeld == true) wake?.release()
        awaiting.toList().also { awaiting.clear() }.forEach { it.success(false) }
        MainActivity.bridge?.pulse()
        super.onDestroy()
    }
}
