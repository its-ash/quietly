# Quietly (package: quietly / com.itsash.quietly)

Automatic phone profiles: "when X, do Y". A native Kotlin foreground service watches
Wi-Fi, time, headphones, Bluetooth and the battery, works out which rules are active
and applies their actions (ringer, Do Not Disturb, volumes, brightness, open an app,
notification). Flutter is only the UI: it edits the rules and shows what is active.

## Rules

A rule has a name, an enabled switch, `restore` (put the old values back when the rule
stops winning a setting), one or more **conditions** (all must match) and **actions**
(done when the rule becomes active). A rule with no conditions never runs. When several
active rules set the same thing, the rule **higher in the list wins**. Slots no rule
sets are left alone.

### JSON schema

Stored as one JSON array in SharedPreferences `quietly_prefs`, key `rules`. Flutter
writes it (`lib/rules/rule.dart`), Kotlin reads it (`Rules.kt` + `RuleJson.kt`). Keep
both in sync; unknown or broken entries are skipped on both sides.

```json
{
  "id": "r1731000000000000", "name": "Office", "enabled": true, "restore": true,
  "conditions": [
    {"type": "wifi", "ssid": "Office"},
    {"type": "time", "start": 1320, "end": 420, "days": [1, 2, 3, 4, 5, 6, 7]},
    {"type": "headphones"},
    {"type": "bluetooth", "address": "AA:BB:CC:DD:EE:FF", "name": "Car"},
    {"type": "charging"},
    {"type": "battery", "below": 20}
  ],
  "actions": [
    {"type": "ringer", "mode": "normal | vibrate | silent"},
    {"type": "dnd", "on": true},
    {"type": "mediaVolume", "percent": 70},
    {"type": "ringVolume", "percent": 50},
    {"type": "brightness", "percent": 40},
    {"type": "openApp", "package": "com.example", "label": "Example"},
    {"type": "notify", "text": "Message"}
  ]
}
```

- `time`: minutes since midnight; `days` are ISO weekdays (1 = Monday .. 7 = Sunday).
  `end < start` is an overnight window and belongs to the day it starts on.
  `start == end` means the whole day.
- `wifi`: exact SSID. Android hides it without Location permission and Location on.
- One condition and one action of each type per rule (the editor enforces it).

Other keys in `quietly_prefs`: `service_enabled` (master switch), `memory` (engine
state), `active_ids` (rules active now, for the UI), `log` (activity log, newest first,
max 50 `{t, rule, on}`), `asked_<permission>`.

## Engine (pure Kotlin, unit tested)

`Rules.kt` (models, `Condition.matches`), `Engine.kt` (`RuleEngine`, `Schedule`,
`ActivityLog`). No Android types, so it runs on the JVM.

- `RuleEngine.reconcile(rules, snapshot, memory, current, canApply)` returns the
  commands to run, the new `Memory`, the rules that switched and the active rules.
- Settings are **slots** (`Slot`): media volume, brightness, ring volume, ringer, Do Not
  Disturb. The first active rule that sets a slot (and `canApply` it) wins.
- Only **differences** are applied: a slot is written when its target changes. The value
  from before the first rule is remembered (`Memory.saved`) and restored when no rule
  wants the slot any more, if the winning rule has `restore` and the user did not change
  the value meanwhile. Percent slots compare with a tolerance (volume steps round).
- `openApp` and `notify` fire once, when a rule becomes active.
- `canApply` skips actions Android would refuse (no Do Not Disturb access for DND or
  silent, no `WRITE_SETTINGS` for brightness), so the next rule can take the slot.
- `Schedule.nextBoundary` gives the next time-window start or end for the alarm.

## Service (Android side)

- `RulesService.kt`: `specialUse` foreground service, low-importance ongoing
  notification ("2 rules active: Office, Night"). Re-evaluates on every `ContextWatcher`
  event and when `rules` changes in prefs. On stop it releases everything (settings put
  back). `START_STICKY`.
- `ContextWatcher.kt`: Wi-Fi `NetworkCallback`, `AudioDeviceCallback` and
  `ACTION_HEADSET_PLUG`, Bluetooth ACL connect/disconnect (seeded from the A2DP/headset
  profiles; needs `BLUETOOTH_CONNECT` on Android 12+), battery/charging, `ACTION_TIME_TICK`
  and an `AlarmManager.setAndAllowWhileIdle` wake-up at time-window boundaries (inexact:
  Doze may delay it a few minutes). Events are debounced (400 ms).
- `ActionRunner.kt`: reads and applies slots; opens apps from the background with a
  1 px overlay (needs "Display over other apps"; Android 15 requires it); notifications.
- `QuietlyPrefs.kt`, `RuleJson.kt`: shared storage and JSON parsing.
- `SystemHooks.kt`: `BootReceiver` (BOOT_COMPLETED, MY_PACKAGE_REPLACED) and
  `RulesTileService` (Quick Settings tile pauses/resumes all rules = the master switch).
- `MainActivity.kt`: the MethodChannel.

## Channel contract

MethodChannel `com.itsash.quietly/control` (`lib/rules/rules_platform.dart`):
`getConfig` -> `{enabled, running, rules (JSON string), active: [id]}`,
`setEnabled({enabled})`, `saveRules({json})`, `status` -> map keyed by `Need` names
(`notifications, location, backgroundLocation, locationServices, bluetooth, dnd,
writeSettings, overlay, battery` + `tileSupported`), `openPermission({name})`,
`getLog`, `clearLog`, `currentSsid`, `bluetoothDevices`, `apps`, `addTile`.
The `Need` enum names in `lib/rules/needs.dart` are the status keys.

## Flutter layout

- `lib/rules/`: `rule.dart` (models + JSON + validation), `kinds.dart` (types, icons,
  descriptions), `needs.dart` (permissions per rule), `templates.dart`,
  `rules_platform.dart`, `rules_store.dart`.
- `lib/screens/`: `home_screen.dart` (switch, missing permissions, reorderable rules,
  active highlighted with `UiStatusPill`), `rule_screen.dart`, `editors.dart` (condition
  and action sheets, permission notices in context), `activity_screen.dart`,
  `settings_screen.dart` (permissions, tile, Updates, Developer).
- `lib/widgets/need_notice.dart`: "Allow" alert shown only while a permission is missing.

## Commands

- `make run`, `make build`, `make test` (analyze + Dart tests), `make test-native`
  (Kotlin engine tests: `android/app/src/test/kotlin/com/itsash/quietly/`; needs one
  `make build` first), `make clean`.
- Icon: `assets/icon/*.svg` -> `rsvg-convert -w 1024 -h 1024` to `*-1024.png`, then
  `dart run flutter_launcher_icons`. Status bar / tile icon:
  `android/app/src/main/res/drawable/ic_stat_quietly.xml`.

## Conventions

- minSdk 26. UI only from `../theme` (read `../theme/COMPONENTS.md`).
- Change engine behaviour only together with tests.
- Only network use: `UiUpdateSection` in Settings. No analytics. Location is used only
  to let Android reveal the Wi-Fi name; coordinates are never read.

## Release (Ash Store)

- `store.json` (id `quietly`, repo its-ash/quietly), `store.mk`, `index.html` +
  `CNAME` (`quietly.itsash.in`). See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version -> build -> commit, tag `vX.Y.Z`, push -> GitHub
  release with `quietly.apk` -> topics, homepage, Pages. Never create releases,
  tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run
  `make store-sync` at the workspace root.
