import 'package:flutter/material.dart';

import 'rule.dart';

/// Something Android makes the user allow. [name] is the key used by the
/// native `status` and `openPermission` calls (MainActivity.kt).
enum Need {
  notifications(
    'Notifications',
    'Android shows a small notification while Quietly watches your rules, and for "Show a notification" actions.',
    Icons.notifications_rounded,
  ),
  battery(
    'Run in the background',
    'Stops Android from closing Quietly to save battery, so rules keep working.',
    Icons.battery_saver_rounded,
  ),
  location(
    'Location permission',
    'Android only tells apps the Wi-Fi network name when they have Location permission. '
        'Quietly never reads or stores where you are.',
    Icons.location_on_rounded,
  ),
  locationServices(
    'Location turned on',
    'Android also needs Location switched on in the quick settings before it shares the Wi-Fi name.',
    Icons.my_location_rounded,
  ),
  backgroundLocation(
    'Location: allow all the time',
    'Without it Android may hide the Wi-Fi name while the app is closed. Choose "Allow all the time" in the app settings.',
    Icons.location_searching_rounded,
  ),
  bluetooth(
    'Nearby devices (Bluetooth)',
    'Needed to list your paired devices and to notice when one connects.',
    Icons.bluetooth_rounded,
  ),
  dnd(
    'Do Not Disturb access',
    'Needed to turn Do Not Disturb on and off and to set the ringer to silent.',
    Icons.do_not_disturb_on_rounded,
  ),
  writeSettings(
    'Modify system settings',
    'Needed to change the screen brightness.',
    Icons.brightness_6_rounded,
  ),
  overlay(
    'Display over other apps',
    'Needed to open an app while Quietly is in the background.',
    Icons.layers_rounded,
  );

  const Need(this.title, this.why, this.icon);

  final String title;
  final String why;
  final IconData icon;

  /// The key for `openPermission` and `status`.
  String get key => name;
}

/// The permissions one rule needs to do its job.
Set<Need> needsOf(Rule rule) => {
  for (final c in rule.conditions)
    ...switch (c) {
      WifiCondition() => const {Need.location, Need.locationServices, Need.backgroundLocation},
      BluetoothCondition() => const {Need.bluetooth},
      _ => const <Need>{},
    },
  for (final a in rule.actions)
    ...switch (a) {
      DndAction() => const {Need.dnd},
      RingerAction(:final mode) when mode == Ringer.silent => const {Need.dnd},
      BrightnessAction() => const {Need.writeSettings},
      OpenAppAction() => const {Need.overlay},
      NotifyAction() => const {Need.notifications},
      _ => const <Need>{},
    },
};
