package com.itsash.quietly

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import kotlin.math.roundToInt

/**
 * Applies engine [Command]s to the phone and reads current values for the engine.
 * Every call is guarded: a failing action (permission revoked, app gone) must never
 * stop the service.
 */
class ActionRunner(private val context: Context) {

    private val main = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(AudioManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)

    /** Reads a slot as the engine's value (percent, ringer mode, 0/1), or null when unknown. */
    fun read(slot: Slot): Int? = try {
        when (slot) {
            Slot.MEDIA_VOLUME -> streamPercent(AudioManager.STREAM_MUSIC)
            Slot.RING_VOLUME -> streamPercent(AudioManager.STREAM_RING)
            Slot.RINGER -> audio?.ringerMode
            Slot.DND -> when (notifications?.currentInterruptionFilter) {
                null, NotificationManager.INTERRUPTION_FILTER_UNKNOWN -> null
                NotificationManager.INTERRUPTION_FILTER_ALL -> 0
                else -> 1
            }
            Slot.BRIGHTNESS -> Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, -1)
                .takeIf { it >= 0 }
                ?.let { (it * 100 / 255f).roundToInt() }
        }
    } catch (_: Throwable) {
        null
    }

    /** False when Android would refuse the change because a special permission is missing. */
    fun canApply(slot: Slot, value: Int): Boolean = when (slot) {
        Slot.DND -> hasPolicyAccess()
        Slot.RINGER -> value != Ringer.SILENT || hasPolicyAccess()
        Slot.BRIGHTNESS -> Settings.System.canWrite(context)
        else -> true
    }

    fun run(command: Command) {
        try {
            when (command) {
                is Command.Apply -> apply(command.slot, command.value)
                is Command.Launch -> launch(command.packageName)
                is Command.Notify -> notify(command.ruleName, command.text)
            }
        } catch (_: Throwable) {
            // Never let one action break the others.
        }
    }

    private fun apply(slot: Slot, value: Int) {
        when (slot) {
            Slot.MEDIA_VOLUME -> setStreamPercent(AudioManager.STREAM_MUSIC, value)
            Slot.RING_VOLUME -> setStreamPercent(AudioManager.STREAM_RING, value)
            Slot.RINGER -> audio?.ringerMode = value
            Slot.DND -> if (hasPolicyAccess()) {
                notifications?.setInterruptionFilter(
                    if (value == 1) NotificationManager.INTERRUPTION_FILTER_PRIORITY else NotificationManager.INTERRUPTION_FILTER_ALL,
                )
            }
            Slot.BRIGHTNESS -> if (Settings.System.canWrite(context)) {
                val resolver = context.contentResolver
                Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
                Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, (value * 255 / 100).coerceIn(1, 255))
            }
        }
    }

    private fun hasPolicyAccess(): Boolean = notifications?.isNotificationPolicyAccessGranted == true

    private fun streamPercent(stream: Int): Int? {
        val am = audio ?: return null
        val max = am.getStreamMaxVolume(stream)
        return if (max > 0) (am.getStreamVolume(stream) * 100f / max).roundToInt() else null
    }

    private fun setStreamPercent(stream: Int, percent: Int) {
        val am = audio ?: return
        val max = am.getStreamMaxVolume(stream)
        am.setStreamVolume(stream, (max * percent / 100f).roundToInt().coerceIn(0, max), 0)
    }

    private fun launch(packageName: String) {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) ?: return
        startFromBackground(intent)
    }

    /**
     * Android blocks activity starts from the background. Apps with "Display over
     * other apps" may start them while they show an overlay window (required from
     * Android 15), so a 1 px invisible overlay is shown for the moment of the start.
     */
    private fun startFromBackground(intent: Intent) {
        if (!Settings.canDrawOverlays(context)) {
            context.startActivity(intent) // works only if Android allows it
            return
        }
        val wm = context.getSystemService(WindowManager::class.java)
        val view = View(context)
        val params = WindowManager.LayoutParams(
            1,
            1,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        )
        main.post {
            var added = false
            try {
                wm.addView(view, params)
                added = true
            } catch (_: Throwable) {
            }
            main.postDelayed({
                try {
                    context.startActivity(intent)
                } catch (_: Throwable) {
                }
                main.postDelayed({ if (added) runCatching { wm.removeView(view) } }, 600)
            }, 60)
        }
    }

    private fun notify(ruleName: String, text: String) {
        val nm = notifications ?: return
        nm.createNotificationChannel(
            NotificationChannel(ALERT_CHANNEL, "Rule alerts", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Messages from rules that show a notification."
            },
        )
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = android.app.Notification.Builder(context, ALERT_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_quietly)
            .setContentTitle(ruleName)
            .setContentText(text.ifBlank { "Rule started" })
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        nm.notify((ruleName + text).hashCode(), notification)
    }

    companion object {
        private const val ALERT_CHANNEL = "rule_alerts"
    }
}
