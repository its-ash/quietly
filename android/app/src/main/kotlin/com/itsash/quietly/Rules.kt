package com.itsash.quietly

/*
 * Pure rule model (no Android types) so the engine can be unit tested on the JVM.
 * Mirrors lib/rules/rule.dart: keep both in sync (schema in CLAUDE.md).
 */

/**
 * Things a rule can set. A slot holds one value; when several active rules set the
 * same slot, the rule higher in the list wins. Enum order is the order values are
 * applied in (volumes before the ringer mode, Do Not Disturb last).
 *
 * Values: percent (0..100) for volumes and brightness, [Ringer] for the ringer,
 * 0 or 1 for Do Not Disturb.
 */
enum class Slot(val key: String, val tolerance: Int) {
    MEDIA_VOLUME("mediaVolume", 8),
    BRIGHTNESS("brightness", 8),
    RING_VOLUME("ringVolume", 8),
    RINGER("ringer", 0),
    DND("dnd", 0);

    companion object {
        fun of(key: String?): Slot? = entries.firstOrNull { it.key == key }
    }
}

/** Same numbers as AudioManager.RINGER_MODE_*. */
object Ringer {
    const val SILENT = 0
    const val VIBRATE = 1
    const val NORMAL = 2

    fun of(key: String?): Int? = when (key) {
        "silent" -> SILENT
        "vibrate" -> VIBRATE
        "normal" -> NORMAL
        else -> null
    }
}

sealed interface Condition {
    /** Connected to the Wi-Fi network with this name. */
    data class Wifi(val ssid: String) : Condition

    /**
     * Between [startMinute] and [endMinute] (minutes since midnight) on the given
     * ISO weekdays (1 = Monday .. 7 = Sunday). A window that ends before it starts
     * runs overnight and belongs to the day it starts on. Start == end means all day.
     */
    data class TimeWindow(val startMinute: Int, val endMinute: Int, val days: Set<Int>) : Condition

    /** Wired or Bluetooth audio output connected. */
    data object Headphones : Condition

    /** A specific Bluetooth device is connected. */
    data class Bluetooth(val address: String, val name: String) : Condition

    data object Charging : Condition

    data class BatteryBelow(val percent: Int) : Condition
}

sealed interface RuleAction {
    /** Sets a [Slot]. */
    data class Set(val slot: Slot, val value: Int) : RuleAction

    /** Starts an app once, when the rule becomes active. */
    data class OpenApp(val packageName: String, val label: String) : RuleAction

    /** Shows a notification once, when the rule becomes active. */
    data class Notify(val text: String) : RuleAction
}

data class Rule(
    val id: String,
    val name: String,
    val enabled: Boolean,
    /** Put the previous values back when the rule stops winning a slot. */
    val restore: Boolean,
    val conditions: List<Condition>,
    val actions: List<RuleAction>,
)

/** Everything the conditions look at, at one moment. */
data class Snapshot(
    val ssid: String?,
    val minuteOfDay: Int,
    /** ISO weekday, 1 = Monday .. 7 = Sunday. */
    val isoDay: Int,
    val headphones: Boolean,
    /** Upper-case MAC addresses of connected Bluetooth devices. */
    val bluetooth: Set<String>,
    val charging: Boolean,
    val battery: Int,
) {
    companion object {
        val EMPTY = Snapshot(null, 0, 1, false, emptySet(), false, 100)
    }
}

fun Condition.matches(s: Snapshot): Boolean = when (this) {
    is Condition.Wifi -> ssid.isNotEmpty() && s.ssid == ssid
    is Condition.TimeWindow -> matchesTime(s.minuteOfDay, s.isoDay)
    Condition.Headphones -> s.headphones
    is Condition.Bluetooth -> address.uppercase() in s.bluetooth
    Condition.Charging -> s.charging
    is Condition.BatteryBelow -> s.battery < percent
}

private fun Condition.TimeWindow.matchesTime(minute: Int, day: Int): Boolean {
    val yesterday = if (day == 1) 7 else day - 1
    return when {
        startMinute == endMinute -> day in days
        startMinute < endMinute -> day in days && minute >= startMinute && minute < endMinute
        // Overnight: the evening part belongs to today, the morning part to the day before.
        else -> (day in days && minute >= startMinute) || (yesterday in days && minute < endMinute)
    }
}
