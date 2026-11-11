import 'package:flutter/material.dart';

import 'rule.dart';

/// The kinds of condition a rule can have, with the text and icon the pickers show.
enum ConditionType {
  wifi('Wi-Fi network', 'While connected to a specific network, like home or the office.', Icons.wifi_rounded),
  time('Time and days', 'During a time window on chosen weekdays. Overnight windows work.', Icons.schedule_rounded),
  headphones('Headphones', 'While wired or Bluetooth headphones are connected.', Icons.headphones_rounded),
  bluetooth('Bluetooth device', 'While one paired device is connected, like your car.', Icons.bluetooth_connected_rounded),
  charging('Charging', 'While the phone is plugged in.', Icons.battery_charging_full_rounded),
  battery('Battery low', 'While the battery is below a level you choose.', Icons.battery_alert_rounded);

  const ConditionType(this.title, this.description, this.icon);

  final String title;
  final String description;
  final IconData icon;

  static ConditionType of(Condition c) => switch (c) {
    WifiCondition() => wifi,
    TimeCondition() => time,
    HeadphonesCondition() => headphones,
    BluetoothCondition() => bluetooth,
    ChargingCondition() => charging,
    BatteryCondition() => battery,
  };
}

/// The kinds of action a rule can have.
enum ActionType {
  ringer('Ringer mode', 'Set the phone to normal, vibrate or silent.', Icons.notifications_active_rounded),
  dnd('Do Not Disturb', 'Turn Do Not Disturb on or off.', Icons.do_not_disturb_on_rounded),
  mediaVolume('Media volume', 'Set the volume of music and video.', Icons.volume_up_rounded),
  ringVolume('Ring volume', 'Set the volume of calls and notifications.', Icons.ring_volume_rounded),
  brightness('Screen brightness', 'Set the screen brightness.', Icons.brightness_6_rounded),
  openApp('Open an app', 'Open an app when the rule starts.', Icons.launch_rounded),
  notify('Show a notification', 'Show a message when the rule starts.', Icons.notifications_rounded);

  const ActionType(this.title, this.description, this.icon);

  final String title;
  final String description;
  final IconData icon;

  static ActionType of(RuleAction a) => switch (a) {
    RingerAction() => ringer,
    DndAction() => dnd,
    MediaVolumeAction() => mediaVolume,
    RingVolumeAction() => ringVolume,
    BrightnessAction() => brightness,
    OpenAppAction() => openApp,
    NotifyAction() => notify,
  };
}

/// "22:00" for minutes since midnight.
String formatMinute(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Short name of an ISO weekday (1 = Mon).
String dayName(int isoDay) => _dayNames[isoDay - 1];

String describeDays(Set<int> days) {
  if (days.length == 7) return 'every day';
  if (days.setEquals(const {1, 2, 3, 4, 5})) return 'weekdays';
  if (days.setEquals(const {6, 7})) return 'weekends';
  return (days.toList()..sort()).map(dayName).join(', ');
}

extension on Set<int> {
  bool setEquals(Set<int> other) => length == other.length && containsAll(other);
}

/// One line for a condition, as shown in lists.
String describeCondition(Condition c) => switch (c) {
  WifiCondition(:final ssid) => ssid.isEmpty ? 'Wi-Fi: choose a network' : 'Connected to $ssid',
  TimeCondition(:final startMinute, :final endMinute, :final days, :final overnight) =>
    '${formatMinute(startMinute)} to ${formatMinute(endMinute)}, ${describeDays(days)}${overnight ? ' (overnight)' : ''}',
  HeadphonesCondition() => 'Headphones connected',
  BluetoothCondition(:final name, :final address) =>
    address.isEmpty ? 'Bluetooth: choose a device' : '${name.isEmpty ? address : name} connected',
  ChargingCondition() => 'Charging',
  BatteryCondition(:final below) => 'Battery below $below%',
};

/// One line for an action, as shown in lists.
String describeAction(RuleAction a) => switch (a) {
  RingerAction(:final mode) => 'Ringer: ${mode.label.toLowerCase()}',
  DndAction(:final on) => on ? 'Do Not Disturb on' : 'Do Not Disturb off',
  MediaVolumeAction(:final percent) => 'Media volume $percent%',
  RingVolumeAction(:final percent) => 'Ring volume $percent%',
  BrightnessAction(:final percent) => 'Brightness $percent%',
  OpenAppAction(:final label, :final packageName) =>
    packageName.isEmpty ? 'Open an app: choose one' : 'Open ${label.isEmpty ? packageName : label}',
  NotifyAction(:final text) => text.isEmpty ? 'Show a notification' : 'Notify: $text',
};

/// A short "when ... then ..." line for a rule card.
String describeRule(Rule r) {
  final when = r.conditions.map(describeCondition).join(' and ');
  final then = r.actions.map(describeAction).join(', ');
  return [if (when.isNotEmpty) 'When $when', if (then.isNotEmpty) then].join('\n');
}
