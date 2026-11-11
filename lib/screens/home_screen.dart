import 'dart:async';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../rules/kinds.dart';
import '../rules/rule.dart';
import '../rules/rules_store.dart';
import '../rules/templates.dart';
import 'activity_screen.dart';
import 'rule_screen.dart';
import 'settings_screen.dart';

/// Master switch, missing permissions and the list of rules (drag to reorder).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final RulesStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _lifecycle;
  Timer? _poll;

  RulesStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.load();
    // Back from a system permission screen: re-check.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        store.load();
        _startPolling();
      },
      onInactive: () => _poll?.cancel(),
    );
    _startPolling();
  }

  /// The service decides which rules are active, so ask it now and then while the screen is visible.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => store.refreshActive());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _pickTemplate() async {
    final template = await UiActionSheet.show<RuleTemplate>(
      context,
      title: 'Templates',
      message: 'Start from a ready-made rule, then adjust it.',
      actions: [
        for (final t in RuleTemplate.all) UiSheetAction(t.name, value: t, icon: t.icon, subtitle: t.summary),
      ],
    );
    if (template != null && mounted) _open(RuleScreen(store: store, rule: template.build(), isNew: true));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => UiScaffold(
        appBar: UiAppBar(
          title: 'Quietly',
          actions: [
            UiIconButton(Icons.auto_awesome_rounded, tooltip: 'Templates', onPressed: _pickTemplate),
            UiIconButton(
              Icons.history_rounded,
              tooltip: 'Activity',
              onPressed: () => _open(ActivityScreen(store: store)),
            ),
            UiIconButton(
              Icons.settings_rounded,
              tooltip: 'Settings',
              onPressed: () => _open(SettingsScreen(store: store)),
            ),
          ],
        ),
        fab: store.ready
            ? UiFab(
                Icons.add_rounded,
                label: 'New rule',
                onPressed: () => _open(RuleScreen(store: store, rule: Rule.create(), isNew: true)),
              )
            : null,
        body: store.ready ? _content(context) : const Center(child: UiSpinner(size: 28)),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final rules = store.rules;
    final missing = store.missing;
    final enabled = store.enabled;
    final running = store.config!.running;
    return ReorderableListView(
      padding: const EdgeInsets.only(bottom: 96),
      buildDefaultDragHandles: false,
      onReorderItem: store.reorder,
      header: UiColumn(
        gap: UiSpace.lg,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiListGroup(
            children: [
              UiSwitchTile(
                'Rules',
                subtitle: !enabled
                    ? 'Paused. Turn on to apply your rules in the background.'
                    : running
                    ? (store.activeIds.isEmpty ? 'On. No rule is active right now.' : 'On. ${store.activeIds.length} active now.')
                    : 'Starting…',
                icon: Icons.nights_stay_rounded,
                status: enabled ? UiStatus.success : UiStatus.neutral,
                value: enabled,
                onChanged: store.setEnabled,
              ),
            ],
          ),
          if (missing.isNotEmpty)
            UiListGroup(
              header: 'Allow',
              footer: 'Tap a row, allow it, then come back.',
              children: [
                for (final need in missing)
                  UiListTile(
                    need.title,
                    subtitle: need.why,
                    icon: Icons.lock_open_rounded,
                    iconStatus: UiStatus.warning,
                    chevron: true,
                    maxSubtitleLines: 3,
                    onTap: () => store.platform.openPermission(need),
                  ),
              ],
            ),
          UiSectionHeader(
            'Rules',
            subtitle: rules.length > 1 ? 'If two active rules set the same thing, the higher one wins. Drag to reorder.' : null,
          ),
          if (rules.isEmpty)
            UiEmptyState(
              compact: true,
              icon: Icons.tune_rounded,
              title: 'No rules yet',
              message: 'A rule says: when this happens, do that. Start from a template or build your own.',
              action: UiButton('Browse templates', icon: Icons.auto_awesome_rounded, onPressed: _pickTemplate),
            ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.only(top: UiSpace.lg),
        child: UiListGroup(
          children: [
            UiListTile(
              'Recent activity',
              subtitle: 'When rules started and stopped',
              icon: Icons.history_rounded,
              chevron: true,
              onTap: () => _open(ActivityScreen(store: store)),
            ),
          ],
        ),
      ),
      children: [
        for (var i = 0; i < rules.length; i++)
          _RuleCard(
            key: ValueKey(rules[i].id),
            index: i,
            rule: rules[i],
            active: store.activeIds.contains(rules[i].id),
            onTap: () => _open(RuleScreen(store: store, rule: rules[i])),
            onToggle: (on) => store.setRuleEnabled(rules[i].id, on),
          ),
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    super.key,
    required this.index,
    required this.rule,
    required this.active,
    required this.onTap,
    required this.onToggle,
  });

  final int index;
  final Rule rule;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: UiSpace.md),
      child: UiCard(
        selected: active,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(UiSpace.lg, UiSpace.md, UiSpace.sm, UiSpace.md),
        child: UiRow(
          gap: UiSpace.md,
          children: [
            Expanded(
              child: UiColumn(
                gap: UiSpace.xs,
                children: [
                  UiRow(
                    children: [
                      Flexible(
                        child: Text(
                          rule.name.isEmpty ? 'Untitled rule' : rule.name,
                          style: text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (active) const UiStatusPill('Active', status: UiStatus.success, pulse: true),
                    ],
                  ),
                  Text(
                    describeRule(rule),
                    style: text.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            UiSwitch(rule.enabled, onChanged: onToggle),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(UiSpace.xs),
                child: Icon(Icons.drag_handle_rounded, color: colors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
