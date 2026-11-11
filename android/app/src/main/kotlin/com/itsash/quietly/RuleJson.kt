package com.itsash.quietly

import org.json.JSONArray
import org.json.JSONObject

/**
 * JSON <-> model. The rules JSON is written by Flutter (lib/rules/rule.dart); this
 * side only reads it. Anything unknown or malformed is skipped, never thrown, so one
 * bad rule cannot stop the service.
 */
object RuleJson {

    fun parseRules(text: String?): List<Rule> {
        if (text.isNullOrBlank()) return emptyList()
        val array = try {
            JSONArray(text)
        } catch (_: Exception) {
            return emptyList()
        }
        return (0 until array.length()).mapNotNull { i ->
            try {
                parseRule(array.getJSONObject(i))
            } catch (_: Exception) {
                null
            }
        }
    }

    private fun parseRule(o: JSONObject): Rule = Rule(
        id = o.getString("id"),
        name = o.optString("name", ""),
        enabled = o.optBoolean("enabled", true),
        restore = o.optBoolean("restore", true),
        conditions = o.optJSONArray("conditions").objects().mapNotNull(::parseCondition),
        actions = o.optJSONArray("actions").objects().mapNotNull(::parseAction),
    )

    private fun parseCondition(o: JSONObject): Condition? = when (o.optString("type")) {
        "wifi" -> Condition.Wifi(o.optString("ssid", ""))
        "time" -> Condition.TimeWindow(
            startMinute = o.optInt("start", 0).coerceIn(0, 1439),
            endMinute = o.optInt("end", 0).coerceIn(0, 1439),
            days = o.optJSONArray("days")?.let { a -> (0 until a.length()).map { a.getInt(it) }.toSet() } ?: (1..7).toSet(),
        )
        "headphones" -> Condition.Headphones
        "bluetooth" -> Condition.Bluetooth(o.optString("address", ""), o.optString("name", ""))
        "charging" -> Condition.Charging
        "battery" -> Condition.BatteryBelow(o.optInt("below", 20))
        else -> null
    }

    private fun parseAction(o: JSONObject): RuleAction? = when (o.optString("type")) {
        "ringer" -> Ringer.of(o.optString("mode"))?.let { RuleAction.Set(Slot.RINGER, it) }
        "dnd" -> RuleAction.Set(Slot.DND, if (o.optBoolean("on", true)) 1 else 0)
        "mediaVolume" -> RuleAction.Set(Slot.MEDIA_VOLUME, o.optInt("percent", 50).coerceIn(0, 100))
        "ringVolume" -> RuleAction.Set(Slot.RING_VOLUME, o.optInt("percent", 50).coerceIn(0, 100))
        "brightness" -> RuleAction.Set(Slot.BRIGHTNESS, o.optInt("percent", 50).coerceIn(0, 100))
        "openApp" -> o.optString("package").takeIf { it.isNotEmpty() }?.let { RuleAction.OpenApp(it, o.optString("label", it)) }
        "notify" -> RuleAction.Notify(o.optString("text", ""))
        else -> null
    }

    private fun JSONArray?.objects(): List<JSONObject> =
        if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

    // Engine memory.

    fun memoryToJson(m: Memory): String = JSONObject()
        .put("active", JSONArray(m.active.toList()))
        .put("applied", JSONObject(m.applied.mapKeys { it.key.key }))
        .put("saved", JSONObject(m.saved.mapKeys { it.key.key }))
        .put("restore", JSONArray(m.restore.map { it.key }))
        .toString()

    fun memoryFromJson(text: String?): Memory {
        if (text.isNullOrBlank()) return Memory()
        return try {
            val o = JSONObject(text)
            Memory(
                active = o.optJSONArray("active")?.strings()?.toSet() ?: emptySet(),
                applied = o.optJSONObject("applied").slots(),
                saved = o.optJSONObject("saved").slots(),
                restore = o.optJSONArray("restore")?.strings()?.mapNotNull(Slot::of)?.toSet() ?: emptySet(),
            )
        } catch (_: Exception) {
            Memory()
        }
    }

    private fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }

    private fun JSONObject?.slots(): Map<Slot, Int> {
        if (this == null) return emptyMap()
        return keys().asSequence().mapNotNull { key -> Slot.of(key)?.let { it to getInt(key) } }.toMap()
    }

    // Activity log.

    fun logToJson(entries: List<LogEntry>): String = JSONArray(
        entries.map { JSONObject().put("t", it.time).put("rule", it.rule).put("on", it.active) },
    ).toString()

    fun logFromJson(text: String?): List<LogEntry> {
        if (text.isNullOrBlank()) return emptyList()
        return try {
            val a = JSONArray(text)
            (0 until a.length()).map {
                val o = a.getJSONObject(it)
                LogEntry(o.getLong("t"), o.getString("rule"), o.getBoolean("on"))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
