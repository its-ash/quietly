package com.itsash.quietly

import java.time.LocalTime
import java.time.ZonedDateTime

/** What the engine remembers between evaluations (persisted by [QuietlyPrefs]). */
data class Memory(
    /** Ids of the rules that were active last time. */
    val active: Set<String> = emptySet(),
    /** What we last set per slot. We only touch a slot again when its target changes. */
    val applied: Map<Slot, Int> = emptyMap(),
    /** The value each slot had before the first rule changed it. */
    val saved: Map<Slot, Int> = emptyMap(),
    /** Slots whose winning rule wants the old value back. */
    val restore: Set<Slot> = emptySet(),
)

sealed interface Command {
    data class Apply(val slot: Slot, val value: Int) : Command
    data class Launch(val packageName: String, val label: String) : Command
    data class Notify(val ruleName: String, val text: String) : Command
}

/** A rule that just became active or inactive. */
data class Switch(val rule: Rule, val active: Boolean)

data class Outcome(
    val commands: List<Command>,
    val memory: Memory,
    val switches: List<Switch>,
    val activeRules: List<Rule>,
)

object RuleEngine {

    private data class Target(val value: Int, val restore: Boolean)

    /** Enabled rules whose conditions all match, in list order. A rule without conditions never runs. */
    fun activeRules(rules: List<Rule>, snapshot: Snapshot): List<Rule> =
        rules.filter { rule -> rule.enabled && rule.conditions.isNotEmpty() && rule.conditions.all { it.matches(snapshot) } }

    /** The value for each slot: the first active rule that sets it (and that can be applied) wins. */
    fun target(active: List<Rule>, canApply: (Slot, Int) -> Boolean = { _, _ -> true }): Map<Slot, Int> =
        targets(active, canApply).mapValues { it.value.value }

    private fun targets(active: List<Rule>, canApply: (Slot, Int) -> Boolean): Map<Slot, Target> {
        val out = linkedMapOf<Slot, Target>()
        for (rule in active) {
            for (action in rule.actions) {
                if (action is RuleAction.Set && action.slot !in out && canApply(action.slot, action.value)) {
                    out[action.slot] = Target(action.value, rule.restore)
                }
            }
        }
        return out
    }

    /**
     * Works out what to do now: which rules are active, which slots need a new value
     * (only changes are applied), which old values to put back, and which one-shot
     * actions (open app, notification) to fire for rules that just became active.
     *
     * [current] reads a slot from the phone (null when unknown). It is used to remember
     * the pre-rule value and to skip restoring a value the user changed meanwhile.
     */
    fun reconcile(
        rules: List<Rule>,
        snapshot: Snapshot,
        memory: Memory,
        current: (Slot) -> Int?,
        canApply: (Slot, Int) -> Boolean = { _, _ -> true },
    ): Outcome {
        val active = activeRules(rules, snapshot)
        val targets = targets(active, canApply)
        val commands = mutableListOf<Command>()
        val applied = memory.applied.toMutableMap()
        val saved = memory.saved.toMutableMap()
        val restore = memory.restore.toMutableSet()

        // Slots no rule wants any more: put the old value back, unless the user changed it.
        for (slot in Slot.entries) {
            if (slot in targets) continue
            val ours = applied.remove(slot) ?: continue
            val original = saved.remove(slot)
            val wantsRestore = restore.remove(slot)
            val now = current(slot)
            if (wantsRestore && original != null && now != null && close(slot, now, ours)) {
                commands += Command.Apply(slot, original)
            }
        }

        // Slots with a new target.
        for (slot in Slot.entries) {
            val t = targets[slot] ?: continue
            if (t.restore) restore += slot else restore -= slot
            if (applied[slot] == t.value) continue
            if (slot !in saved) current(slot)?.let { saved[slot] = it }
            applied[slot] = t.value
            commands += Command.Apply(slot, t.value)
        }

        // One-shot actions and log entries for rules that switched.
        val activeIds = active.map { it.id }.toSet()
        val switches = mutableListOf<Switch>()
        for (rule in active) {
            if (rule.id in memory.active) continue
            switches += Switch(rule, true)
            for (action in rule.actions) {
                when (action) {
                    is RuleAction.OpenApp -> commands += Command.Launch(action.packageName, action.label)
                    is RuleAction.Notify -> commands += Command.Notify(rule.name, action.text)
                    is RuleAction.Set -> Unit
                }
            }
        }
        for (rule in rules) {
            if (rule.id in memory.active && rule.id !in activeIds) switches += Switch(rule, false)
        }

        return Outcome(
            commands = commands,
            memory = Memory(activeIds, applied, saved, restore),
            switches = switches,
            activeRules = active,
        )
    }

    /** Stop everything: put back every value we changed. Used when the service stops. */
    fun releaseAll(memory: Memory, current: (Slot) -> Int?): Outcome =
        reconcile(emptyList(), Snapshot.EMPTY, memory, current)

    /** Percent slots are rounded to the device's volume steps, so compare with a tolerance. */
    private fun close(slot: Slot, a: Int, b: Int): Boolean = kotlin.math.abs(a - b) <= slot.tolerance
}

/** One line of the activity log. */
data class LogEntry(val time: Long, val rule: String, val active: Boolean)

object ActivityLog {
    const val MAX = 50

    /** Newest first, at most [max] entries. */
    fun append(existing: List<LogEntry>, added: List<LogEntry>, max: Int = MAX): List<LogEntry> =
        (added.sortedByDescending { it.time } + existing).take(max)
}

object Schedule {
    /**
     * The next moment after [now] when a time window of an enabled rule starts or ends,
     * or null if no rule has a time condition. Used to wake the phone for the change.
     */
    fun nextBoundary(rules: List<Rule>, now: ZonedDateTime): ZonedDateTime? {
        val minutes = rules
            .filter { it.enabled }
            .flatMap { rule -> rule.conditions.filterIsInstance<Condition.TimeWindow>() }
            .flatMap { listOf(it.startMinute, it.endMinute) }
            .toSortedSet()
        if (minutes.isEmpty()) return null
        for (offset in 0L..1L) {
            val date = now.toLocalDate().plusDays(offset)
            for (m in minutes) {
                val at = ZonedDateTime.of(date, LocalTime.of(m / 60, m % 60), now.zone)
                if (at.isAfter(now)) return at
            }
        }
        return null
    }
}
