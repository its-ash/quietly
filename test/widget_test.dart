import 'package:flutter_test/flutter_test.dart';
import 'package:quietly/rules/kinds.dart';
import 'package:quietly/rules/needs.dart';
import 'package:quietly/rules/rule.dart';
import 'package:quietly/rules/rules_platform.dart';
import 'package:quietly/rules/rules_store.dart';
import 'package:quietly/rules/templates.dart';

/// Keeps what would be saved natively, so the store can be tested without a phone.
class FakePlatform extends RulesPlatform {
  FakePlatform([this.saved = '[]']);

  String saved;

  @override
  Future<RulesConfig> config() async => RulesConfig(
    enabled: true,
    running: true,
    rules: Rule.listFromJson(saved),
    activeIds: const {},
  );

  @override
  Future<RulesStatus> status() async => const RulesStatus({'notifications': true, 'battery': true});

  @override
  Future<void> saveRules(List<Rule> rules) async => saved = Rule.listToJson(rules);
}

Rule rule(String id, {List<Condition>? conditions, List<RuleAction>? actions}) => Rule(
  id: id,
  name: id,
  conditions: conditions ?? const [ChargingCondition()],
  actions: actions ?? const [DndAction(on: true)],
);

void main() {
  group('rule JSON', () {
    test('round trips every condition and action', () {
      final original = Rule(
        id: 'r1',
        name: 'Everything',
        restore: false,
        conditions: const [
          WifiCondition('Office'),
          TimeCondition(startMinute: 1320, endMinute: 420, days: {1, 2, 3}),
          HeadphonesCondition(),
          BluetoothCondition(address: 'AA:BB', name: 'Car'),
          ChargingCondition(),
          BatteryCondition(below: 15),
        ],
        actions: const [
          RingerAction(Ringer.silent),
          DndAction(on: false),
          MediaVolumeAction(70),
          RingVolumeAction(30),
          BrightnessAction(20),
          OpenAppAction(packageName: 'com.maps', label: 'Maps'),
          NotifyAction('Hi'),
        ],
      );
      final back = Rule.listFromJson(Rule.listToJson([original])).single;
      expect(Rule.listToJson([back]), Rule.listToJson([original]));
      expect(back.restore, isFalse);
      expect(back.conditions.length, 6);
      expect(back.actions.length, 7);
    });

    test('the wire format is what the Kotlin side reads', () {
      expect(const TimeCondition(startMinute: 60, endMinute: 120, days: {3, 1}).toJson(), {
        'type': 'time',
        'start': 60,
        'end': 120,
        'days': [1, 3],
      });
      expect(const RingerAction(Ringer.vibrate).toJson(), {'type': 'ringer', 'mode': 'vibrate'});
      expect(const OpenAppAction(packageName: 'p', label: 'L').toJson(), {'type': 'openApp', 'package': 'p', 'label': 'L'});
    });

    test('broken input is skipped, not thrown', () {
      expect(Rule.listFromJson('nope'), isEmpty);
      expect(Rule.listFromJson('{}'), isEmpty);
      final rules = Rule.listFromJson(
        '[{"name":"no id"},{"id":"a","conditions":[{"type":"x"},{"type":"charging"}],"actions":[{"type":"ringer","mode":"loud"}]}]',
      );
      expect(rules.single.conditions.length, 1);
      expect(rules.single.actions.single, isA<RingerAction>());
    });
  });

  group('validation', () {
    test('needs a name, a condition and an action', () {
      expect(const Rule(id: 'a', name: '').problem, isNotNull);
      expect(const Rule(id: 'a', name: 'x').problem, 'Add at least one condition.');
      expect(const Rule(id: 'a', name: 'x', conditions: [ChargingCondition()]).problem, 'Add at least one action.');
      expect(rule('a').problem, isNull);
    });

    test('templates that need a pick are not valid until finished', () {
      expect(RuleTemplate.office.build().problem, 'Enter a Wi-Fi network name.');
      expect(RuleTemplate.car.build().problem, 'Pick a Bluetooth device.');
      expect(RuleTemplate.night.build().problem, isNull);
      expect(RuleTemplate.headphones.build().problem, isNull);
    });
  });

  group('permissions', () {
    test('each rule asks only for what it uses', () {
      expect(needsOf(rule('a', actions: const [MediaVolumeAction(50)])), isEmpty);
      expect(needsOf(rule('a', actions: const [RingerAction(Ringer.vibrate)])), isEmpty);
      expect(needsOf(rule('a', actions: const [RingerAction(Ringer.silent)])), {Need.dnd});
      expect(needsOf(rule('a', conditions: const [WifiCondition('x')], actions: const [MediaVolumeAction(50)])), {
        Need.location,
        Need.locationServices,
        Need.backgroundLocation,
      });
      expect(needsOf(rule('a', actions: const [BrightnessAction(30), OpenAppAction(packageName: 'p', label: 'P')])), {
        Need.writeSettings,
        Need.overlay,
      });
    });
  });

  group('descriptions', () {
    test('overnight windows say so', () {
      expect(
        describeCondition(const TimeCondition(startMinute: 23 * 60, endMinute: 7 * 60)),
        '23:00 to 07:00, every day (overnight)',
      );
      expect(describeDays(const {1, 2, 3, 4, 5}), 'weekdays');
      expect(describeDays(const {6, 7}), 'weekends');
      expect(describeDays(const {1, 3}), 'Mon, Wed');
    });
  });

  group('RulesStore', () {
    test('save adds, replaces and removes', () async {
      final platform = FakePlatform();
      final store = RulesStore(platform: platform);
      await store.load();

      await store.save(rule('a'));
      await store.save(rule('b'));
      await store.save(rule('a').copyWith(name: 'A2'));
      expect(store.rules.map((r) => r.name), ['A2', 'b']);

      await store.remove('b');
      expect(Rule.listFromJson(platform.saved).map((r) => r.id), ['a']);
    });

    test('reorder moves a rule to its final position and is saved', () async {
      final platform = FakePlatform(Rule.listToJson([rule('a'), rule('b'), rule('c')]));
      final store = RulesStore(platform: platform);
      await store.load();

      await store.reorder(0, 2); // drag a to the end
      expect(store.rules.map((r) => r.id), ['b', 'c', 'a']);
      await store.reorder(2, 0); // drag a back to the top
      expect(Rule.listFromJson(platform.saved).map((r) => r.id), ['a', 'b', 'c']);
    });

    test('toggling a rule keeps the rest', () async {
      final store = RulesStore(platform: FakePlatform(Rule.listToJson([rule('a'), rule('b')])));
      await store.load();
      await store.setRuleEnabled('b', false);
      expect(store.rules.map((r) => r.enabled), [true, false]);
    });

    test('missing lists app-wide needs plus those of enabled rules', () async {
      final store = RulesStore(
        platform: FakePlatform(
          Rule.listToJson([
            rule('on', actions: const [RingerAction(Ringer.silent)]),
            rule('off', actions: const [BrightnessAction(30)]).copyWith(enabled: false),
          ]),
        ),
      );
      await store.load();
      // Notifications and battery are granted in the fake; Do Not Disturb is not.
      expect(store.missing, [Need.dnd]);
    });
  });
}
