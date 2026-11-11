import 'package:flutter/foundation.dart';

import 'needs.dart';
import 'rule.dart';
import 'rules_platform.dart';

/// UI state: the rules, the master switch and the phone's permissions. Every
/// change is saved natively first, so the background service picks it up even
/// when the app is closed.
class RulesStore extends ChangeNotifier {
  RulesStore({this.platform = const RulesPlatform()});

  final RulesPlatform platform;

  RulesConfig? config;
  RulesStatus? status;
  List<Rule> _rules = const [];

  bool get ready => config != null && status != null;
  List<Rule> get rules => _rules;
  bool get enabled => config?.enabled ?? false;
  Set<String> get activeIds => config?.activeIds ?? const {};

  Future<void> load() async {
    final c = await platform.config();
    status = await platform.status();
    config = c;
    _rules = c.rules;
    notifyListeners();
  }

  /// Re-reads which rules are active, without touching the list being edited.
  Future<void> refreshActive() async {
    final old = config;
    final fresh = await platform.config();
    if (old != null && fresh.running == old.running && fresh.enabled == old.enabled && setEquals(fresh.activeIds, old.activeIds)) {
      return;
    }
    config = RulesConfig(enabled: fresh.enabled, running: fresh.running, rules: _rules, activeIds: fresh.activeIds);
    notifyListeners();
  }

  Future<void> setEnabled(bool on) async {
    await platform.setEnabled(on);
    // The service starts asynchronously; read back after it had a moment.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await load();
  }

  /// Adds a new rule at the end of the list, or replaces the one with the same id.
  Future<void> save(Rule rule) {
    final list = [..._rules];
    final i = list.indexWhere((r) => r.id == rule.id);
    if (i < 0) {
      list.add(rule);
    } else {
      list[i] = rule;
    }
    return _commit(list);
  }

  Future<void> remove(String id) => _commit([..._rules]..removeWhere((r) => r.id == id));

  Future<void> setRuleEnabled(String id, bool enabled) =>
      _commit([for (final r in _rules) r.id == id ? r.copyWith(enabled: enabled) : r]);

  /// Moves a rule. [newIndex] is the final position, as in `ReorderableListView.onReorderItem`.
  Future<void> reorder(int oldIndex, int newIndex) {
    final list = [..._rules];
    list.insert(newIndex, list.removeAt(oldIndex));
    return _commit(list);
  }

  Future<void> _commit(List<Rule> rules) async {
    _rules = rules;
    notifyListeners();
    await platform.saveRules(rules);
  }

  /// Permissions that apply to the whole app, plus those the enabled rules need.
  List<Need> get missing {
    final s = status;
    if (s == null) return const [];
    final wanted = <Need>{
      Need.notifications,
      Need.battery,
      for (final r in _rules)
        if (r.enabled) ...needsOf(r),
    };
    return [
      for (final need in Need.values)
        if (wanted.contains(need) && !s.has(need)) need,
    ];
  }
}
