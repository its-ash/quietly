package com.itsash.quietly

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.service.quicksettings.TileService

/**
 * Foreground service that keeps the rules applied. It re-evaluates on every event
 * from [ContextWatcher] and whenever the rules change, applies only the differences
 * ([RuleEngine]) and, when it stops, puts every changed setting back.
 * All work happens on the main thread.
 */
class RulesService : Service(), SharedPreferences.OnSharedPreferenceChangeListener {

    private lateinit var prefs: QuietlyPrefs
    private lateinit var runner: ActionRunner
    private lateinit var watcher: ContextWatcher
    private lateinit var notifications: NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = QuietlyPrefs(this)
        runner = ActionRunner(this)
        notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL, "Rules running", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while Quietly watches your rules."
                setShowBadge(false)
            },
        )
        startForegroundCompat(notification("Quietly is starting", "Checking your rules."))
        watcher = ContextWatcher(this) { evaluate() }
        watcher.start()
        prefs.prefs.registerOnSharedPreferenceChangeListener(this)
        current = this
        evaluate()
        refreshTile()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!prefs.serviceEnabled) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        current = null
        prefs.prefs.unregisterOnSharedPreferenceChangeListener(this)
        watcher.stop()
        // Put everything back: rules are paused when the service is not running.
        val outcome = RuleEngine.releaseAll(prefs.memory, runner::read)
        outcome.commands.forEach(runner::run)
        prefs.memory = outcome.memory
        prefs.activeIds = emptySet()
        refreshTile()
        super.onDestroy()
    }

    override fun onSharedPreferenceChanged(sp: SharedPreferences?, key: String?) {
        when (key) {
            QuietlyPrefs.KEY_RULES -> evaluate()
            QuietlyPrefs.KEY_ENABLED -> if (!prefs.serviceEnabled) stopSelf()
        }
    }

    private fun evaluate() {
        val rules = prefs.rules
        val outcome = RuleEngine.reconcile(rules, watcher.snapshot(), prefs.memory, runner::read, runner::canApply)
        outcome.commands.forEach(runner::run)
        prefs.memory = outcome.memory
        prefs.activeIds = outcome.activeRules.map { it.id }.toSet()
        val now = System.currentTimeMillis()
        prefs.appendLog(outcome.switches.map { LogEntry(now, it.rule.name.ifBlank { "Untitled rule" }, it.active) })
        watcher.scheduleBoundary(rules)

        val names = outcome.activeRules.map { it.name.ifBlank { "Untitled rule" } }
        val (title, text) = when {
            names.isEmpty() -> "No rules active" to "Quietly is watching. Tap to edit your rules."
            else -> "${names.size} ${if (names.size == 1) "rule" else "rules"} active: ${names.joinToString()}" to
                "Tap to edit your rules."
        }
        notifications.notify(NOTIFICATION_ID, notification(title, text))
    }

    private fun notification(title: String, text: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_quietly)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun refreshTile() {
        TileService.requestListeningState(this, ComponentName(this, RulesTileService::class.java))
    }

    companion object {
        private const val CHANNEL = "rules_service"
        private const val NOTIFICATION_ID = 8

        @Volatile
        private var current: RulesService? = null

        /** True while the service is alive in this process. */
        val running: Boolean get() = current != null

        fun start(context: Context) {
            context.startForegroundService(Intent(context, RulesService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RulesService::class.java))
        }

        /** Applies the master switch: starts or stops the service. */
        fun sync(context: Context) {
            if (QuietlyPrefs(context).serviceEnabled) start(context) else stop(context)
        }

        /** Re-evaluates now (e.g. after the user granted a permission). Main thread only. */
        fun refresh() {
            current?.evaluate()
        }
    }
}
