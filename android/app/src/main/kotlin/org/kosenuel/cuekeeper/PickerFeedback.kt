package org.kosenuel.cuekeeper

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.SystemClock
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View

/** One short, original tick. Never queues feedback or plays over silent mode. */
class PickerFeedback(private val context: Context) {
    private var loaded = false
    private var last = -100L
    private val pool = SoundPool.Builder().setMaxStreams(1).setAudioAttributes(
        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
    private val sound: Int
    init {
        pool.setOnLoadCompleteListener { _, _, status -> loaded = status == 0 }
        sound = pool.load(context, R.raw.picker_tick, 1)
    }
    fun tick(view: View, mode: String) {
        val now = SystemClock.elapsedRealtime()
        if (now - last < 65 || mode == "off") return
        last = now
        if (mode == "haptics" || mode == "both") view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if ((mode == "sound" || mode == "both") && loaded && audio.ringerMode == AudioManager.RINGER_MODE_NORMAL &&
            Settings.System.getInt(context.contentResolver, Settings.System.SOUND_EFFECTS_ENABLED, 0) != 0)
            pool.play(sound, .32f, .32f, 0, 0, 1f)
    }
}
