import 'dart:convert';

/// The rule model and its JSON form. The JSON is stored natively and read by
/// the Kotlin engine (`Rules.kt`, `RuleJson.kt`): keep both in sync. The schema
/// is documented in CLAUDE.md.

/// Ringer mode. The JSON value is [name].
enum Ringer {
  normal('Normal'),
  vibrate('Vibrate'),
  silent('Silent');

  const Ringer(this.label);

  final String label;

  static Ringer of(String? name) => values.firstWhere((r) => r.name == name, orElse: () => Ringer.normal);
}

/// A thing that must be true for a rule to run. All conditions of a rule must match.
sealed class Condition {
  const Condition();

  Map<String, Object?> toJson();

  /// Null for an unknown or broken entry.
  static Condition? fromJson(Object? json) {
    if (json is! Map) return null;
    return switch (json['type']) {
      'wifi' => WifiCondition((json['ssid'] as String?) ?? ''),
      'time' => TimeCondition(
        startMinute: (json['start'] as num?)?.toInt() ?? 0,
        endMinute: (json['end'] as num?)?.toInt() ?? 0,
        days: {for (final d in (json['days'] as List?) ?? const <Object?>[]) (d as num).toInt()},
      ),
      'headphones' => const HeadphonesCondition(),
      'bluetooth' => BluetoothCondition(address: (json['address'] as String?) ?? '', name: (json['name'] as String?) ?? ''),
      'charging' => const ChargingCondition(),
      'battery' => BatteryCondition(below: (json['below'] as num?)?.toInt() ?? 20),
      _ => null,
    };
  }
}

/// Connected to the Wi-Fi network with this name.
final class WifiCondition extends Condition {
  const WifiCondition(this.ssid);

  final String ssid;

  @override
  Map<String, Object?> toJson() => {'type': 'wifi', 'ssid': ssid};
}

/// Between [startMinute] and [endMinute] (minutes since midnight) on [days]
/// (ISO weekdays, 1 = Monday .. 7 = Sunday). A window that ends before it
/// starts runs overnight and belongs to the day it starts on.
final class TimeCondition extends Condition {
  const TimeCondition({required this.startMinute, required this.endMinute, this.days = allDays});

  static const allDays = {1, 2, 3, 4, 5, 6, 7};

  final int startMinute;
  final int endMinute;
  final Set<int> days;

  bool get overnight => endMinute < startMinute;

  @override
  Map<String, Object?> toJson() => {
    'type': 'time',
    'start': startMinute,
    'end': endMinute,
    'days': (days.toList()..sort()),
  };
}

/// Wired or Bluetooth headphones connected.
final class HeadphonesCondition extends Condition {
  const HeadphonesCondition();

  @override
  Map<String, Object?> toJson() => {'type': 'headphones'};
}

/// A specific Bluetooth device is connected.
final class BluetoothCondition extends Condition {
  const BluetoothCondition({required this.address, required this.name});

  final String address;
  final String name;

  @override
  Map<String, Object?> toJson() => {'type': 'bluetooth', 'address': address, 'name': name};
}

final class ChargingCondition extends Condition {
  const ChargingCondition();

  @override
  Map<String, Object?> toJson() => {'type': 'charging'};
}

/// Battery level below [below] percent.
final class BatteryCondition extends Condition {
  const BatteryCondition({required this.below});

  final int below;

  @override
  Map<String, Object?> toJson() => {'type': 'battery', 'below': below};
}

/// Something done when a rule becomes active.
sealed class RuleAction {
  const RuleAction();

  Map<String, Object?> toJson();

  /// Null for an unknown or broken entry.
  static RuleAction? fromJson(Object? json) {
    if (json is! Map) return null;
    int percent() => ((json['percent'] as num?)?.toInt() ?? 50).clamp(0, 100);
    return switch (json['type']) {
      'ringer' => RingerAction(Ringer.of(json['mode'] as String?)),
      'dnd' => DndAction(on: (json['on'] as bool?) ?? true),
      'mediaVolume' => MediaVolumeAction(percent()),
      'ringVolume' => RingVolumeAction(percent()),
      'brightness' => BrightnessAction(percent()),
      'openApp' => OpenAppAction(packageName: (json['package'] as String?) ?? '', label: (json['label'] as String?) ?? ''),
      'notify' => NotifyAction((json['text'] as String?) ?? ''),
      _ => null,
    };
  }
}

final class RingerAction extends RuleAction {
  const RingerAction(this.mode);

  final Ringer mode;

  @override
  Map<String, Object?> toJson() => {'type': 'ringer', 'mode': mode.name};
}

/// Do Not Disturb on or off.
final class DndAction extends RuleAction {
  const DndAction({required this.on});

  final bool on;

  @override
  Map<String, Object?> toJson() => {'type': 'dnd', 'on': on};
}

final class MediaVolumeAction extends RuleAction {
  const MediaVolumeAction(this.percent);

  final int percent;

  @override
  Map<String, Object?> toJson() => {'type': 'mediaVolume', 'percent': percent};
}

final class RingVolumeAction extends RuleAction {
  const RingVolumeAction(this.percent);

  final int percent;

  @override
  Map<String, Object?> toJson() => {'type': 'ringVolume', 'percent': percent};
}

final class BrightnessAction extends RuleAction {
  const BrightnessAction(this.percent);

  final int percent;

  @override
  Map<String, Object?> toJson() => {'type': 'brightness', 'percent': percent};
}

final class OpenAppAction extends RuleAction {
  const OpenAppAction({required this.packageName, required this.label});

  final String packageName;
  final String label;

  @override
  Map<String, Object?> toJson() => {'type': 'openApp', 'package': packageName, 'label': label};
}

final class NotifyAction extends RuleAction {
  const NotifyAction(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'type': 'notify', 'text': text};
}

/// "When all [conditions] match, do [actions]." Rules higher in the list win
/// when two active rules set the same thing.
class Rule {
  const Rule({
    required this.id,
    required this.name,
    this.enabled = true,
    this.restore = true,
    this.conditions = const [],
    this.actions = const [],
  });

  factory Rule.create({String name = '', List<Condition> conditions = const [], List<RuleAction> actions = const []}) =>
      Rule(id: 'r${DateTime.now().microsecondsSinceEpoch}', name: name, conditions: conditions, actions: actions);

  /// Null when [json] has no id.
  static Rule? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    return Rule(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      enabled: (json['enabled'] as bool?) ?? true,
      restore: (json['restore'] as bool?) ?? true,
      conditions: [for (final c in (json['conditions'] as List?) ?? const <Object?>[]) ?Condition.fromJson(c)],
      actions: [for (final a in (json['actions'] as List?) ?? const <Object?>[]) ?RuleAction.fromJson(a)],
    );
  }

  /// Parses the JSON array stored natively. Broken entries are skipped.
  static List<Rule> listFromJson(String? text) {
    if (text == null || text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return [for (final r in decoded) ?Rule.fromJson(r)];
    } on FormatException {
      return const [];
    }
  }

  static String listToJson(List<Rule> rules) => jsonEncode([for (final r in rules) r.toJson()]);

  final String id;
  final String name;
  final bool enabled;

  /// Put the previous settings back when the rule stops matching.
  final bool restore;
  final List<Condition> conditions;
  final List<RuleAction> actions;

  Rule copyWith({
    String? name,
    bool? enabled,
    bool? restore,
    List<Condition>? conditions,
    List<RuleAction>? actions,
  }) => Rule(
    id: id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    restore: restore ?? this.restore,
    conditions: conditions ?? this.conditions,
    actions: actions ?? this.actions,
  );

  /// Why the rule cannot be saved yet, or null.
  String? get problem {
    if (name.trim().isEmpty) return 'Give the rule a name.';
    if (conditions.isEmpty) return 'Add at least one condition.';
    if (actions.isEmpty) return 'Add at least one action.';
    for (final c in conditions) {
      switch (c) {
        case WifiCondition(:final ssid) when ssid.trim().isEmpty:
          return 'Enter a Wi-Fi network name.';
        case BluetoothCondition(:final address) when address.isEmpty:
          return 'Pick a Bluetooth device.';
        case TimeCondition(:final days) when days.isEmpty:
          return 'Pick at least one day.';
        default:
      }
    }
    for (final a in actions) {
      if (a is OpenAppAction && a.packageName.isEmpty) return 'Pick an app to open.';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'restore': restore,
    'conditions': [for (final c in conditions) c.toJson()],
    'actions': [for (final a in actions) a.toJson()],
  };
}
