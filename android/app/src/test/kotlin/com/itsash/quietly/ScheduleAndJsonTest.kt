package com.itsash.quietly

import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ScheduleAndJsonTest {

    private val zone = ZoneId.of("Europe/Berlin")
    private fun at(day: Int, h: Int, m: Int) = ZonedDateTime.of(2026, 3, day, h, m, 0, 0, zone)

    private fun withTime(start: Int, end: Int, enabled: Boolean = true) = Rule(
        "t", "t", enabled, true,
        listOf(Condition.TimeWindow(start, end, (1..7).toSet())),
        listOf(RuleAction.Set(Slot.DND, 1)),
    )

    @Test
    fun nextBoundaryIsTheNextStartOrEnd() {
        val rules = listOf(withTime(22 * 60, 7 * 60))
        assertEquals(at(10, 22, 0), Schedule.nextBoundary(rules, at(10, 12, 0)))
        assertEquals(at(11, 7, 0), Schedule.nextBoundary(rules, at(10, 23, 0)))
        assertEquals("a boundary that is exactly now is already past", at(10, 22, 0), Schedule.nextBoundary(rules, at(10, 7, 0)))
    }

    @Test
    fun nextBoundaryTakesTheEarliestOfAllRules() {
        val rules = listOf(withTime(22 * 60, 7 * 60), withTime(9 * 60, 17 * 60))
        assertEquals(at(10, 9, 0), Schedule.nextBoundary(rules, at(10, 8, 0)))
        assertEquals(at(10, 17, 0), Schedule.nextBoundary(rules, at(10, 9, 30)))
    }

    @Test
    fun noTimeConditionsMeansNoAlarm() {
        assertNull(Schedule.nextBoundary(emptyList(), at(10, 8, 0)))
        assertNull(Schedule.nextBoundary(listOf(withTime(60, 120, enabled = false)), at(10, 8, 0)))
    }

    @Test
    fun parsesEveryConditionAndAction() {
        val json = """
            [{
              "id": "r1", "name": "Everything", "enabled": true, "restore": false,
              "conditions": [
                {"type": "wifi", "ssid": "Office"},
                {"type": "time", "start": 1320, "end": 420, "days": [1, 2, 3]},
                {"type": "headphones"},
                {"type": "bluetooth", "address": "AA:BB", "name": "Car"},
                {"type": "charging"},
                {"type": "battery", "below": 15},
                {"type": "from-the-future"}
              ],
              "actions": [
                {"type": "ringer", "mode": "vibrate"},
                {"type": "dnd", "on": true},
                {"type": "mediaVolume", "percent": 70},
                {"type": "ringVolume", "percent": 30},
                {"type": "brightness", "percent": 20},
                {"type": "openApp", "package": "com.maps", "label": "Maps"},
                {"type": "notify", "text": "Hi"},
                {"type": "ringer", "mode": "loud"}
              ]
            }, {"name": "broken, no id"}]
        """.trimIndent()

        val rules = RuleJson.parseRules(json)
        assertEquals(1, rules.size)
        val r = rules.single()
        assertEquals("Everything", r.name)
        assertEquals(false, r.restore)
        assertEquals(
            listOf(
                Condition.Wifi("Office"),
                Condition.TimeWindow(1320, 420, setOf(1, 2, 3)),
                Condition.Headphones,
                Condition.Bluetooth("AA:BB", "Car"),
                Condition.Charging,
                Condition.BatteryBelow(15),
            ),
            r.conditions,
        )
        assertEquals(
            listOf(
                RuleAction.Set(Slot.RINGER, Ringer.VIBRATE),
                RuleAction.Set(Slot.DND, 1),
                RuleAction.Set(Slot.MEDIA_VOLUME, 70),
                RuleAction.Set(Slot.RING_VOLUME, 30),
                RuleAction.Set(Slot.BRIGHTNESS, 20),
                RuleAction.OpenApp("com.maps", "Maps"),
                RuleAction.Notify("Hi"),
            ),
            r.actions,
        )
    }

    @Test
    fun garbageParsesToNothing() {
        assertEquals(emptyList<Rule>(), RuleJson.parseRules(null))
        assertEquals(emptyList<Rule>(), RuleJson.parseRules("not json"))
        assertEquals(Memory(), RuleJson.memoryFromJson("{"))
    }

    @Test
    fun memoryAndLogRoundTrip() {
        val memory = Memory(
            active = setOf("a", "b"),
            applied = mapOf(Slot.RINGER to 1, Slot.MEDIA_VOLUME to 70),
            saved = mapOf(Slot.RINGER to 2),
            restore = setOf(Slot.RINGER),
        )
        assertEquals(memory, RuleJson.memoryFromJson(RuleJson.memoryToJson(memory)))

        val log = listOf(LogEntry(5, "Office", true), LogEntry(3, "Night", false))
        assertEquals(log, RuleJson.logFromJson(RuleJson.logToJson(log)))
    }
}
