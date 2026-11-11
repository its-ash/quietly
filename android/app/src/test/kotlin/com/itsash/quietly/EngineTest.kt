package com.itsash.quietly

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EngineTest {

    private fun snap(
        ssid: String? = null,
        minute: Int = 12 * 60,
        day: Int = 3,
        headphones: Boolean = false,
        bluetooth: Set<String> = emptySet(),
        charging: Boolean = false,
        battery: Int = 80,
    ) = Snapshot(ssid, minute, day, headphones, bluetooth, charging, battery)

    private fun rule(
        id: String,
        conditions: List<Condition>,
        actions: List<RuleAction>,
        restore: Boolean = true,
        enabled: Boolean = true,
    ) = Rule(id, id, enabled, restore, conditions, actions)

    private val office = rule("office", listOf(Condition.Wifi("Office")), listOf(RuleAction.Set(Slot.RINGER, Ringer.VIBRATE)))

    /** A phone whose settings we can read and that applies commands. */
    private class Phone(vararg initial: Pair<Slot, Int>) {
        val values = mutableMapOf(*initial)
        fun read(slot: Slot): Int? = values[slot]
        fun run(commands: List<Command>) {
            commands.filterIsInstance<Command.Apply>().forEach { values[it.slot] = it.value }
        }
    }

    // Conditions.

    @Test
    fun wifiMatchesExactName() {
        assertTrue(Condition.Wifi("Office").matches(snap(ssid = "Office")))
        assertFalse(Condition.Wifi("Office").matches(snap(ssid = "office")))
        assertFalse(Condition.Wifi("Office").matches(snap(ssid = null)))
        assertFalse(Condition.Wifi("").matches(snap(ssid = "")))
    }

    @Test
    fun daytimeWindow() {
        val c = Condition.TimeWindow(9 * 60, 17 * 60, setOf(1, 2, 3, 4, 5))
        assertTrue(c.matches(snap(minute = 9 * 60, day = 1)))
        assertTrue(c.matches(snap(minute = 16 * 60 + 59, day = 5)))
        assertFalse(c.matches(snap(minute = 17 * 60, day = 5)))
        assertFalse(c.matches(snap(minute = 8 * 60 + 59, day = 2)))
        assertFalse("weekend", c.matches(snap(minute = 12 * 60, day = 6)))
    }

    @Test
    fun overnightWindowBelongsToTheDayItStarts() {
        // 22:00 to 07:00, Friday only.
        val c = Condition.TimeWindow(22 * 60, 7 * 60, setOf(5))
        assertTrue("Friday 23:00", c.matches(snap(minute = 23 * 60, day = 5)))
        assertTrue("Saturday 06:59 is still Friday's window", c.matches(snap(minute = 6 * 60 + 59, day = 6)))
        assertFalse("Saturday 07:00", c.matches(snap(minute = 7 * 60, day = 6)))
        assertFalse("Saturday 23:00 starts a new window that is not enabled", c.matches(snap(minute = 23 * 60, day = 6)))
        assertFalse("Friday 06:00 belongs to Thursday's window", c.matches(snap(minute = 6 * 60, day = 5)))
    }

    @Test
    fun overnightWindowWrapsSundayToMonday() {
        val c = Condition.TimeWindow(23 * 60, 6 * 60, setOf(7))
        assertTrue(c.matches(snap(minute = 5 * 60, day = 1)))
        assertFalse(c.matches(snap(minute = 5 * 60, day = 2)))
    }

    @Test
    fun equalStartAndEndMeansAllDay() {
        val c = Condition.TimeWindow(0, 0, setOf(2))
        assertTrue(c.matches(snap(minute = 800, day = 2)))
        assertFalse(c.matches(snap(minute = 800, day = 3)))
    }

    @Test
    fun deviceAndPowerConditions() {
        assertTrue(Condition.Headphones.matches(snap(headphones = true)))
        assertTrue(Condition.Bluetooth("aa:bb", "Car").matches(snap(bluetooth = setOf("AA:BB"))))
        assertFalse(Condition.Bluetooth("AA:BB", "Car").matches(snap()))
        assertTrue(Condition.Charging.matches(snap(charging = true)))
        assertTrue(Condition.BatteryBelow(20).matches(snap(battery = 19)))
        assertFalse(Condition.BatteryBelow(20).matches(snap(battery = 20)))
    }

    // Active rules.

    @Test
    fun allConditionsMustMatch() {
        val r = rule(
            "r",
            listOf(Condition.Wifi("Office"), Condition.Charging),
            listOf(RuleAction.Set(Slot.DND, 1)),
        )
        assertTrue(RuleEngine.activeRules(listOf(r), snap(ssid = "Office")).isEmpty())
        assertEquals(listOf(r), RuleEngine.activeRules(listOf(r), snap(ssid = "Office", charging = true)))
    }

    @Test
    fun disabledAndEmptyRulesNeverRun() {
        val off = office.copy(id = "off", enabled = false)
        val empty = rule("empty", emptyList(), listOf(RuleAction.Set(Slot.DND, 1)))
        assertTrue(RuleEngine.activeRules(listOf(off, empty), snap(ssid = "Office")).isEmpty())
    }

    // Conflicts.

    @Test
    fun ruleHigherInTheListWins() {
        val night = rule("night", listOf(Condition.Charging), listOf(RuleAction.Set(Slot.RINGER, Ringer.SILENT), RuleAction.Set(Slot.DND, 1)))
        val target = RuleEngine.target(RuleEngine.activeRules(listOf(office, night), snap(ssid = "Office", charging = true)))
        assertEquals(Ringer.VIBRATE, target[Slot.RINGER])
        assertEquals("slots only the lower rule sets still apply", 1, target[Slot.DND])

        val reversed = RuleEngine.target(RuleEngine.activeRules(listOf(night, office), snap(ssid = "Office", charging = true)))
        assertEquals(Ringer.SILENT, reversed[Slot.RINGER])
    }

    @Test
    fun actionsThatCannotBeAppliedFallThroughToTheNextRule() {
        val first = rule("a", listOf(Condition.Charging), listOf(RuleAction.Set(Slot.DND, 1)))
        val second = rule("b", listOf(Condition.Charging), listOf(RuleAction.Set(Slot.DND, 0)))
        val noDnd = { slot: Slot, value: Int -> !(slot == Slot.DND && value == 1) }
        assertEquals(0, RuleEngine.target(listOf(first, second), noDnd)[Slot.DND])
    }

    // Reconcile.

    @Test
    fun appliesRuleThenRestoresThePreviousValue() {
        val phone = Phone(Slot.RINGER to Ringer.NORMAL)

        val on = RuleEngine.reconcile(listOf(office), snap(ssid = "Office"), Memory(), phone::read)
        assertEquals(listOf<Command>(Command.Apply(Slot.RINGER, Ringer.VIBRATE)), on.commands)
        assertEquals(listOf(Switch(office, true)), on.switches)
        assertEquals(Ringer.NORMAL, on.memory.saved[Slot.RINGER])
        phone.run(on.commands)

        val off = RuleEngine.reconcile(listOf(office), snap(ssid = "Home"), on.memory, phone::read)
        assertEquals(listOf<Command>(Command.Apply(Slot.RINGER, Ringer.NORMAL)), off.commands)
        assertEquals(listOf(Switch(office, false)), off.switches)
        assertEquals(Memory(), off.memory)
    }

    @Test
    fun onlyDifferencesAreApplied() {
        val phone = Phone(Slot.RINGER to Ringer.NORMAL)
        val first = RuleEngine.reconcile(listOf(office), snap(ssid = "Office"), Memory(), phone::read)
        phone.run(first.commands)
        val again = RuleEngine.reconcile(listOf(office), snap(ssid = "Office", battery = 50), first.memory, phone::read)
        assertTrue(again.commands.isEmpty())
        assertTrue(again.switches.isEmpty())
    }

    @Test
    fun doesNotFightTheUser() {
        val phone = Phone(Slot.RINGER to Ringer.NORMAL)
        val on = RuleEngine.reconcile(listOf(office), snap(ssid = "Office"), Memory(), phone::read)
        phone.run(on.commands)
        // The user switches to silent while the rule is active: not undone, and not restored later.
        phone.values[Slot.RINGER] = Ringer.SILENT
        val still = RuleEngine.reconcile(listOf(office), snap(ssid = "Office"), on.memory, phone::read)
        assertTrue(still.commands.isEmpty())
        val off = RuleEngine.reconcile(listOf(office), snap(ssid = null), on.memory, phone::read)
        assertTrue(off.commands.isEmpty())
    }

    @Test
    fun withoutRestoreTheValueStays() {
        val r = office.copy(restore = false)
        val phone = Phone(Slot.RINGER to Ringer.NORMAL)
        val on = RuleEngine.reconcile(listOf(r), snap(ssid = "Office"), Memory(), phone::read)
        phone.run(on.commands)
        val off = RuleEngine.reconcile(listOf(r), snap(ssid = null), on.memory, phone::read)
        assertTrue(off.commands.isEmpty())
        assertTrue(off.memory.applied.isEmpty())
    }

    @Test
    fun savedValueSurvivesHandoverBetweenRules() {
        val night = rule("night", listOf(Condition.Charging), listOf(RuleAction.Set(Slot.RINGER, Ringer.SILENT)))
        val phone = Phone(Slot.RINGER to Ringer.NORMAL)
        val rules = listOf(office, night)

        val a = RuleEngine.reconcile(rules, snap(ssid = "Office"), Memory(), phone::read)
        phone.run(a.commands)
        // Office still wins; night joining changes nothing.
        val b = RuleEngine.reconcile(rules, snap(ssid = "Office", charging = true), a.memory, phone::read)
        assertTrue(b.commands.isEmpty())
        // Leaving the office hands the slot to night.
        val c = RuleEngine.reconcile(rules, snap(charging = true), b.memory, phone::read)
        assertEquals(listOf<Command>(Command.Apply(Slot.RINGER, Ringer.SILENT)), c.commands)
        phone.run(c.commands)
        // Unplugging restores the value from before any rule.
        val d = RuleEngine.reconcile(rules, snap(), c.memory, phone::read)
        assertEquals(listOf<Command>(Command.Apply(Slot.RINGER, Ringer.NORMAL)), d.commands)
    }

    @Test
    fun volumeRestoreToleratesRounding() {
        val r = rule("car", listOf(Condition.Charging), listOf(RuleAction.Set(Slot.MEDIA_VOLUME, 70)))
        val phone = Phone(Slot.MEDIA_VOLUME to 20)
        val on = RuleEngine.reconcile(listOf(r), snap(charging = true), Memory(), phone::read)
        // The phone has 15 steps, so 70% becomes 67%.
        phone.values[Slot.MEDIA_VOLUME] = 67
        val off = RuleEngine.reconcile(listOf(r), snap(), on.memory, phone::read)
        assertEquals(listOf<Command>(Command.Apply(Slot.MEDIA_VOLUME, 20)), off.commands)
    }

    @Test
    fun commandsFollowSlotOrder() {
        val r = rule(
            "all",
            listOf(Condition.Charging),
            listOf(RuleAction.Set(Slot.DND, 1), RuleAction.Set(Slot.RINGER, Ringer.SILENT), RuleAction.Set(Slot.MEDIA_VOLUME, 10)),
        )
        val out = RuleEngine.reconcile(listOf(r), snap(charging = true), Memory(), { null })
        assertEquals(listOf(Slot.MEDIA_VOLUME, Slot.RINGER, Slot.DND), out.commands.map { (it as Command.Apply).slot })
    }

    @Test
    fun oneShotActionsFireOnlyWhenTheRuleStarts() {
        val r = rule(
            "drive",
            listOf(Condition.Bluetooth("AA", "Car")),
            listOf(RuleAction.OpenApp("maps", "Maps"), RuleAction.Notify("Driving")),
        )
        val on = RuleEngine.reconcile(listOf(r), snap(bluetooth = setOf("AA")), Memory(), { null })
        assertEquals(listOf(Command.Launch("maps", "Maps"), Command.Notify("drive", "Driving")), on.commands)
        val again = RuleEngine.reconcile(listOf(r), snap(bluetooth = setOf("AA")), on.memory, { null })
        assertTrue(again.commands.isEmpty())
    }

    @Test
    fun releaseAllPutsEverythingBack() {
        val phone = Phone(Slot.RINGER to Ringer.NORMAL, Slot.DND to 0)
        val r = rule("r", listOf(Condition.Charging), listOf(RuleAction.Set(Slot.RINGER, Ringer.VIBRATE), RuleAction.Set(Slot.DND, 1)))
        val on = RuleEngine.reconcile(listOf(r), snap(charging = true), Memory(), phone::read)
        phone.run(on.commands)
        val off = RuleEngine.releaseAll(on.memory, phone::read)
        assertEquals(setOf<Command>(Command.Apply(Slot.RINGER, Ringer.NORMAL), Command.Apply(Slot.DND, 0)), off.commands.toSet())
        assertEquals(Memory(), off.memory)
    }

    @Test
    fun deletingARuleReleasesItsSlots() {
        val phone = Phone(Slot.RINGER to Ringer.NORMAL)
        val on = RuleEngine.reconcile(listOf(office), snap(ssid = "Office"), Memory(), phone::read)
        phone.run(on.commands)
        val gone = RuleEngine.reconcile(emptyList(), snap(ssid = "Office"), on.memory, phone::read)
        assertEquals(listOf<Command>(Command.Apply(Slot.RINGER, Ringer.NORMAL)), gone.commands)
    }

    // Log.

    @Test
    fun logKeepsTheNewest50() {
        val old = (1..50).map { LogEntry(it.toLong(), "r", true) }.reversed()
        val updated = ActivityLog.append(old, listOf(LogEntry(100, "new", false)))
        assertEquals(50, updated.size)
        assertEquals("new", updated.first().rule)
        assertEquals(2L, updated.last().time)
    }
}
