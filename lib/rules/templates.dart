import 'package:flutter/material.dart';

import 'rule.dart';

/// A ready-made rule to start from. Templates open in the editor so the user
/// can finish them (pick the Wi-Fi network or the car) before saving.
class RuleTemplate {
  const RuleTemplate({
    required this.name,
    required this.summary,
    required this.icon,
    required this.conditions,
    required this.actions,
  });

  final String name;
  final String summary;
  final IconData icon;
  final List<Condition> conditions;
  final List<RuleAction> actions;

  Rule build() => Rule.create(name: name, conditions: conditions, actions: actions);

  static const all = [office, night, car, headphones];

  static const office = RuleTemplate(
    name: 'Office',
    summary: 'Vibrate at work. You pick the Wi-Fi network.',
    icon: Icons.business_center_rounded,
    conditions: [WifiCondition('')],
    actions: [RingerAction(Ringer.vibrate)],
  );

  static const night = RuleTemplate(
    name: 'Night',
    summary: 'Do Not Disturb from 23:00 to 07:00.',
    icon: Icons.bedtime_rounded,
    conditions: [TimeCondition(startMinute: 23 * 60, endMinute: 7 * 60)],
    actions: [DndAction(on: true)],
  );

  static const car = RuleTemplate(
    name: 'Car',
    summary: 'Media volume 70% when your car connects. You pick the device.',
    icon: Icons.directions_car_rounded,
    conditions: [BluetoothCondition(address: '', name: '')],
    actions: [MediaVolumeAction(70)],
  );

  static const headphones = RuleTemplate(
    name: 'Headphones',
    summary: 'Media volume 40% when headphones connect.',
    icon: Icons.headphones_rounded,
    conditions: [HeadphonesCondition()],
    actions: [MediaVolumeAction(40)],
  );
}
