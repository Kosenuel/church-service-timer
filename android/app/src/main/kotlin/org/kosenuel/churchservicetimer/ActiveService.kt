package org.kosenuel.churchservicetimer

import android.app.*
import android.content.*
import android.graphics.drawable.Icon
import android.os.*
import android.content.pm.ServiceInfo
import io.flutter.plugin.common.MethodChannel

/** The service card: current segment with a countdown Android draws itself,
 * plus Pause/Resume and Next. Next needs a second tap within five seconds,
 * matching the app's confirm-before-acting rule. The foreground service shows
 * it while running; otherwise it is posted as an ordinary ongoing notification,
 * so adding controls never changes when the foreground service runs. */
object ServiceCard {
    const val NOTICE = 701
    /** The ordinary notification uses its own ID, so stopping the foreground
     * service (which removes notice 701) cannot remove it. */
    private const val STANDALONE = 704
    const val CHANNEL = "active-service"
    const val PAUSE = "org.kosenuel.churchservicetimer.action.PAUSE"
    const val NEXT = "org.kosenuel.churchservicetimer.action.NEXT"
    private const val CONFIRM_MS = 5000L
    private val handler = Handler(Looper.getMainLooper())
    var card: Map<*, *>? = null
        private set
    private var nextArmedUntil = 0L
    private var appContext: Context? = null
    private val disarm = Runnable { nextArmedUntil = 0L; appContext?.let { show(it) } }

    val active get() = card?.get("active") == true

    fun ensureChannel(c: Context) {
        if (Build.VERSION.SDK_INT >= 26) c.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel(CHANNEL, "Active service timing", NotificationManager.IMPORTANCE_LOW))
    }

    /** Replaces the card and shows it, through the service when it runs. */
    fun update(c: Context, next: Map<*, *>) {
        appContext = c.applicationContext
        card = next
        show(c)
    }

    fun show(c: Context) {
        val manager = c.getSystemService(NotificationManager::class.java)
        try {
            when {
                ActiveService.running -> { manager.cancel(STANDALONE); manager.notify(NOTICE, build(c)) }
                active -> { ensureChannel(c); manager.notify(STANDALONE, build(c)) }
                else -> manager.cancel(STANDALONE)
            }
        } catch (_: Exception) { /* Notification permission may have been withdrawn. */ }
    }

    fun clear(c: Context) {
        card = null
        c.getSystemService(NotificationManager::class.java).cancel(STANDALONE)
    }

    fun onAction(c: Context, action: String?) {
        appContext = c.applicationContext
        // After process death nothing can act on the tap: remove the stale card.
        // Tapping the notification body still opens the app to recover.
        if (MainActivity.bridge == null) { clear(c); return }
        when (action) {
            PAUSE -> MainActivity.bridge?.notificationAction("pause")
            NEXT -> {
                val now = SystemClock.elapsedRealtime()
                handler.removeCallbacks(disarm)
                if (nextArmedUntil > now) {
                    nextArmedUntil = 0L
                    MainActivity.bridge?.notificationAction("next")
                } else {
                    nextArmedUntil = now + CONFIRM_MS
                    handler.postDelayed(disarm, CONFIRM_MS)
                }
                show(c)
            }
        }
    }

    private fun action(c: Context, name: String, code: Int) = PendingIntent.getBroadcast(c, code,
        Intent(c, ServiceActionReceiver::class.java).setAction(name),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    @Suppress("DEPRECATION")
    fun build(c: Context): Notification {
        val open = MainActivity.openApp(c, NOTICE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
        builder.setSmallIcon(R.drawable.ic_warning_notification).setOngoing(true).setOnlyAlertOnce(true)
            .setContentIntent(open).setCategory(Notification.CATEGORY_SERVICE)
        val card = this.card
        if (card == null || card["active"] != true) {
            return builder.setContentTitle("Church Service Timer is active")
                .setContentText("Display timing and warnings · tap to return").build()
        }
        val segment = card["segment"] as? String ?: ""
        val next = card["next"] as? String ?: ""
        val title = card["title"] as? String ?: ""
        val paused = card["paused"] == true
        val overtime = card["overtime"] == true
        val deadline = (card["deadlineWall"] as? Number)?.toLong()
        builder.setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentTitle(when { paused -> "Paused · $segment"; overtime -> "Overtime · $segment"; else -> segment })
            .setSubText(title)
            .setContentText(when {
                deadline == null -> "${card["remaining"]}${if (next.isNotEmpty()) " · Next: $next" else ""}"
                next.isNotEmpty() -> "Next: $next"
                else -> "Final segment"
            })
        if (deadline != null) {
            // Android animates the clock; it counts up from zero once overtime.
            builder.setWhen(deadline).setShowWhen(true).setUsesChronometer(true)
                .setChronometerCountDown(!overtime)
        } else builder.setShowWhen(false)
        val icon = Icon.createWithResource(c, R.drawable.ic_warning_notification)
        if (card["canPause"] == true)
            builder.addAction(Notification.Action.Builder(icon, if (paused) "Resume" else "Pause", action(c, PAUSE, 702)).build())
        if (card["canNext"] == true) {
            val armed = nextArmedUntil > SystemClock.elapsedRealtime()
            builder.addAction(Notification.Action.Builder(icon,
                if (armed) "Tap again: Next segment" else "Next segment", action(c, NEXT, 703)).build())
        }
        return builder.build()
    }
}

/** Private receiver for the card's buttons; forwards them to the running app. */
class ServiceActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = ServiceCard.onAction(context, intent.action)
}

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
        fun stop(context: Context) {
            running = false
            context.stopService(Intent(context, ActiveService::class.java))
            // The card continues as an ordinary notification while a service runs.
            ServiceCard.show(context)
        }
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
            ServiceCard.ensureChannel(this)
            val notification = ServiceCard.build(this)
            if (Build.VERSION.SDK_INT >= 29) startForeground(ServiceCard.NOTICE, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            else startForeground(ServiceCard.NOTICE, notification)
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
