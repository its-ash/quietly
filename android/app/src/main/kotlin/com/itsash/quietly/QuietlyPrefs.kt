package com.itsash.quietly

import android.content.Context
import android.content.SharedPreferences

/**
 * Settings shared by the Flutter UI (through MainActivity), the Quick Settings tile,
 * the boot receiver and RulesService, which re-evaluates when the rules change.
 */
class QuietlyPrefs(context: Context) {
    val prefs: SharedPreferences = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Master switch: the service runs (and rules apply) only while this is on. */
    var serviceEnabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(v) = prefs.edit().putBoolean(KEY_ENABLED, v).apply()

    /** The rules as written by Flutter: a JSON array (schema in CLAUDE.md). */
    var rulesJson: String
        get() = prefs.getString(KEY_RULES, "[]") ?: "[]"
        set(v) = prefs.edit().putString(KEY_RULES, v).apply()

    val rules: List<Rule>
        get() = RuleJson.parseRules(rulesJson)

    var memory: Memory
        get() = RuleJson.memoryFromJson(prefs.getString(KEY_MEMORY, null))
        set(v) = prefs.edit().putString(KEY_MEMORY, RuleJson.memoryToJson(v)).apply()

    /** Ids of the rules active right now, for the UI. */
    var activeIds: Set<String>
        get() = prefs.getStringSet(KEY_ACTIVE, emptySet()) ?: emptySet()
        set(v) = prefs.edit().putStringSet(KEY_ACTIVE, v).apply()

    var log: List<LogEntry>
        get() = RuleJson.logFromJson(prefs.getString(KEY_LOG, null))
        set(v) = prefs.edit().putString(KEY_LOG, RuleJson.logToJson(v)).apply()

    fun appendLog(added: List<LogEntry>) {
        if (added.isNotEmpty()) log = ActivityLog.append(log, added)
    }

    /** True once we asked for [key] with the system dialog; after that we open Settings instead. */
    fun asked(key: String): Boolean = prefs.getBoolean("asked_$key", false)

    fun markAsked(key: String) = prefs.edit().putBoolean("asked_$key", true).apply()

    companion object {
        const val FILE = "quietly_prefs"
        const val KEY_ENABLED = "service_enabled"
        const val KEY_RULES = "rules"
        const val KEY_MEMORY = "memory"
        const val KEY_ACTIVE = "active_ids"
        const val KEY_LOG = "log"
    }
}
