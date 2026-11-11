import 'package:flutter/services.dart';

import 'needs.dart';
import 'rule.dart';

/// Everything the background service reads, as saved on the phone.
class RulesConfig {
  const RulesConfig({required this.enabled, required this.running, required this.rules, required this.activeIds});

  factory RulesConfig.fromMap(Map<Object?, Object?> map) => RulesConfig(
    enabled: map['enabled'] as bool? ?? false,
    running: map['running'] as bool? ?? false,
    rules: Rule.listFromJson(map['rules'] as String?),
    activeIds: {for (final id in (map['active'] as List?) ?? const <Object?>[]) id as String},
  );

  final bool enabled;
  final bool running;
  final List<Rule> rules;

  /// Rules that match right now.
  final Set<String> activeIds;
}

/// Which permissions are granted on this phone.
class RulesStatus {
  const RulesStatus(this._map);

  final Map<Object?, Object?> _map;

  bool has(Need need) => _map[need.key] as bool? ?? false;
  bool get tileSupported => _map['tileSupported'] as bool? ?? false;
}

/// One line of the activity log: a rule started or stopped.
class ActivityEntry {
  const ActivityEntry({required this.time, required this.rule, required this.active});

  final DateTime time;
  final String rule;
  final bool active;
}

class InstalledApp {
  const InstalledApp({required this.label, required this.packageName});

  final String label;
  final String packageName;
}

class PairedDevice {
  const PairedDevice({required this.name, required this.address});

  final String name;
  final String address;
}

/// Dart side of MethodChannel "com.itsash.quietly/control" (MainActivity.kt).
class RulesPlatform {
  const RulesPlatform();

  static const _channel = MethodChannel('com.itsash.quietly/control');

  Future<RulesConfig> config() async =>
      RulesConfig.fromMap(await _channel.invokeMapMethod<Object?, Object?>('getConfig') ?? const {});

  Future<RulesStatus> status() async =>
      RulesStatus(await _channel.invokeMapMethod<Object?, Object?>('status') ?? const {});

  Future<void> setEnabled(bool enabled) => _channel.invokeMethod('setEnabled', {'enabled': enabled});

  /// Saves the rules. The running service re-evaluates at once.
  Future<void> saveRules(List<Rule> rules) => _channel.invokeMethod('saveRules', {'json': Rule.listToJson(rules)});

  Future<void> openPermission(Need need) => _channel.invokeMethod('openPermission', {'name': need.key});

  Future<List<ActivityEntry>> log() async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('getLog') ?? const [];
    return [
      for (final e in list)
        ActivityEntry(
          time: DateTime.fromMillisecondsSinceEpoch((e['time'] as num).toInt()),
          rule: e['rule'] as String? ?? '',
          active: e['active'] as bool? ?? false,
        ),
    ];
  }

  Future<void> clearLog() => _channel.invokeMethod('clearLog');

  /// The Wi-Fi network the phone is on, or null (not on Wi-Fi, or Android hides the name).
  Future<String?> currentSsid() => _channel.invokeMethod<String>('currentSsid');

  Future<List<PairedDevice>> pairedDevices() async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('bluetoothDevices') ?? const [];
    return [for (final d in list) PairedDevice(name: d['name'] as String? ?? '', address: d['address'] as String? ?? '')];
  }

  Future<List<InstalledApp>> apps() async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('apps') ?? const [];
    return [
      for (final a in list) InstalledApp(label: a['label'] as String? ?? '', packageName: a['package'] as String? ?? ''),
    ];
  }

  Future<bool> addTile() async => await _channel.invokeMethod<bool>('addTile') ?? false;
}
