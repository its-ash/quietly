# Quietly

Automatic phone profiles: when you reach the office, go silent. At night, Do Not Disturb.

**[Website](https://quietly.itsash.in)** · **[Download APK](https://github.com/its-ash/quietly/releases/latest/download/quietly.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Rules**: "when X, do Y". A rule has one or more conditions (all must match)
  and actions that run when it starts. Turn a rule off without deleting it.
- **Conditions**: a Wi-Fi network, a time window on chosen weekdays (overnight
  windows like 22:00 to 07:00 work), headphones connected, a Bluetooth device
  (your car), charging, battery below a level.
- **Actions**: ringer mode (normal, vibrate, silent), Do Not Disturb on or off,
  media volume, ring volume, screen brightness, open an app, show a notification.
- **Conflicts**: if two active rules set the same thing, the one higher in your
  list wins. Drag to reorder.
- **Puts things back**: when a rule stops, your old settings return, unless you
  changed them yourself in the meantime.
- **Templates**: Office, Night, Car and Headphones, to start quickly.
- **Runs in the background**, starts again after a reboot, and has a Quick
  Settings tile to pause all rules. A recent activity log shows when rules
  started and stopped.
- **Private**: everything stays on your phone. The only network call is the
  update check in Settings.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update Quietly from it.
- **APK**: download the [latest APK](https://github.com/its-ash/quietly/releases/latest/download/quietly.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

Requires Android 8.0 (API 26) or later.

Android asks you to allow a few things, each only for the rules that use it:

| Permission | Needed for |
|---|---|
| Location + Location turned on | Android only shares the Wi-Fi network name with apps that have it. Quietly never reads where you are. |
| Nearby devices (Bluetooth) | Listing paired devices and noticing when one connects |
| Do Not Disturb access | Do Not Disturb and the silent ringer mode |
| Modify system settings | Screen brightness |
| Display over other apps | Opening an app from the background |
| Notifications, battery optimisation | The status notification, and keeping rules running |

## Develop

Needs Flutter ≥ 3.44 and the shared theme package at `../theme`.

```bash
make run          # run on a connected device
make test         # flutter analyze + flutter test
make test-native  # Kotlin rule-engine tests on the JVM
make build        # release APK
make deploy       # bump version, build, tag, push, GitHub release (see store.mk)
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the
version in `pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes
a GitHub release with `quietly.apk`. Ash Store and the website pick up the new
version from that release.

## Project layout

```
lib/
├── main.dart                     # UiApp + HomeScreen
├── rules/
│   ├── rule.dart                 # Rule, conditions, actions, JSON, validation
│   ├── kinds.dart                # condition/action types, icons, descriptions
│   ├── needs.dart                # permissions each rule needs
│   ├── templates.dart            # Office, Night, Car, Headphones
│   ├── rules_platform.dart       # MethodChannel to MainActivity.kt
│   └── rules_store.dart          # rules, switch, permissions state
├── screens/
│   ├── home_screen.dart          # switch, permissions, reorderable rules
│   ├── rule_screen.dart          # edit one rule
│   ├── editors.dart              # condition and action editor sheets
│   ├── activity_screen.dart      # recent rule switches
│   └── settings_screen.dart
└── widgets/need_notice.dart
android/app/src/main/kotlin/com/itsash/quietly/
├── Rules.kt, Engine.kt           # pure rule engine (unit tested)
├── RuleJson.kt, QuietlyPrefs.kt  # shared storage
├── RulesService.kt               # foreground service
├── ContextWatcher.kt             # Wi-Fi, audio, Bluetooth, battery, clock
├── ActionRunner.kt               # applies the actions
├── SystemHooks.kt                # boot receiver, Quick Settings tile
└── MainActivity.kt               # MethodChannel
```

See `CLAUDE.md` for the rule schema and details.

## License

No license file is included yet.

Built by [itsash.in](https://itsash.in).
