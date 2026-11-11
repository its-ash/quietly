import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../rules/kinds.dart';
import '../rules/needs.dart';
import '../rules/rule.dart';
import '../rules/rules_store.dart';
import '../widgets/need_notice.dart';
import 'editors.dart';

/// Create or edit one rule: name, conditions ("when"), actions ("then").
class RuleScreen extends StatefulWidget {
  const RuleScreen({super.key, required this.store, required this.rule, this.isNew = false});

  final RulesStore store;
  final Rule rule;

  /// A rule that is not in the list yet (it is added on Save).
  final bool isNew;

  @override
  State<RuleScreen> createState() => _RuleScreenState();
}

class _RuleScreenState extends State<RuleScreen> {
  late Rule _rule = widget.rule;
  late final _name = TextEditingController(text: widget.rule.name);

  RulesStore get store => widget.store;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Rule get _current => _rule.copyWith(name: _name.text.trim());

  Future<void> _addCondition() async {
    final type = await UiActionSheet.show<ConditionType>(
      context,
      title: 'Add a condition',
      message: 'All conditions must be true for the rule to run.',
      actions: [
        for (final t in ConditionType.values)
          UiSheetAction(
            t.title,
            value: t,
            icon: t.icon,
            subtitle: t.description,
            // One condition of each kind keeps rules easy to read.
            enabled: !_rule.conditions.any((c) => ConditionType.of(c) == t),
          ),
      ],
    );
    if (type == null || !mounted) return;
    final condition = await editCondition(context, store, type);
    if (condition != null) setState(() => _rule = _rule.copyWith(conditions: [..._rule.conditions, condition]));
  }

  Future<void> _editCondition(int i) async {
    final old = _rule.conditions[i];
    final condition = await editCondition(context, store, ConditionType.of(old), old);
    if (condition == null) return;
    setState(() => _rule = _rule.copyWith(conditions: [..._rule.conditions]..[i] = condition));
  }

  Future<void> _addAction() async {
    final type = await UiActionSheet.show<ActionType>(
      context,
      title: 'Add an action',
      message: 'Done when the rule starts. Anything you change can be put back when it stops.',
      actions: [
        for (final t in ActionType.values)
          UiSheetAction(
            t.title,
            value: t,
            icon: t.icon,
            subtitle: t.description,
            enabled: !_rule.actions.any((a) => ActionType.of(a) == t),
          ),
      ],
    );
    if (type == null || !mounted) return;
    final action = await editAction(context, store, type);
    if (action != null) setState(() => _rule = _rule.copyWith(actions: [..._rule.actions, action]));
  }

  Future<void> _editAction(int i) async {
    final old = _rule.actions[i];
    final action = await editAction(context, store, ActionType.of(old), old);
    if (action == null) return;
    setState(() => _rule = _rule.copyWith(actions: [..._rule.actions]..[i] = action));
  }

  Future<void> _save() async {
    final rule = _current;
    final problem = rule.problem;
    if (problem != null) {
      context.showToast(problem, status: UiStatus.warning);
      return;
    }
    await store.save(rule);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await UiDialog.confirm(
      context,
      title: 'Delete this rule?',
      message: 'Anything it changed is put back if it is active now.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await store.remove(_rule.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final needs = needsOf(_current);
    return UiScaffold(
      appBar: UiAppBar(
        title: widget.isNew ? 'New rule' : 'Edit rule',
        actions: [
          if (!widget.isNew) UiIconButton(Icons.delete_outline_rounded, tooltip: 'Delete rule', onPressed: _delete),
        ],
      ),
      scrollable: true,
      body: UiColumn(
        gap: UiSpace.lg,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiTextField(
            label: 'Name',
            hint: 'Office, Night, Car…',
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          UiListGroup(
            header: 'When',
            footer: 'The rule runs while all of these are true.',
            children: [
              for (var i = 0; i < _rule.conditions.length; i++)
                UiListTile(
                  describeCondition(_rule.conditions[i]),
                  subtitle: ConditionType.of(_rule.conditions[i]).title,
                  icon: ConditionType.of(_rule.conditions[i]).icon,
                  maxSubtitleLines: 1,
                  trailing: UiIconButton(
                    Icons.close_rounded,
                    tooltip: 'Remove',
                    size: UiSize.sm,
                    onPressed: () => setState(
                      () => _rule = _rule.copyWith(conditions: [..._rule.conditions]..removeAt(i)),
                    ),
                  ),
                  onTap: () => _editCondition(i),
                ),
              UiListTile(
                'Add condition',
                icon: Icons.add_rounded,
                iconStatus: UiStatus.info,
                onTap: _addCondition,
              ),
            ],
          ),
          UiListGroup(
            header: 'Then',
            footer: 'If two active rules set the same thing, the one higher in your list wins.',
            children: [
              for (var i = 0; i < _rule.actions.length; i++)
                UiListTile(
                  describeAction(_rule.actions[i]),
                  subtitle: ActionType.of(_rule.actions[i]).title,
                  icon: ActionType.of(_rule.actions[i]).icon,
                  maxSubtitleLines: 1,
                  trailing: UiIconButton(
                    Icons.close_rounded,
                    tooltip: 'Remove',
                    size: UiSize.sm,
                    onPressed: () => setState(
                      () => _rule = _rule.copyWith(actions: [..._rule.actions]..removeAt(i)),
                    ),
                  ),
                  onTap: () => _editAction(i),
                ),
              UiListTile('Add action', icon: Icons.add_rounded, iconStatus: UiStatus.info, onTap: _addAction),
            ],
          ),
          UiListGroup(
            children: [
              UiSwitchTile(
                'Put things back',
                subtitle: 'When the rule stops, restore the ringer, volume and other settings it changed.',
                icon: Icons.settings_backup_restore_rounded,
                value: _rule.restore,
                onChanged: (v) => setState(() => _rule = _rule.copyWith(restore: v)),
              ),
              UiSwitchTile(
                'Enabled',
                subtitle: 'Turn a rule off without deleting it.',
                icon: Icons.power_settings_new_rounded,
                value: _rule.enabled,
                onChanged: (v) => setState(() => _rule = _rule.copyWith(enabled: v)),
              ),
            ],
          ),
          for (final need in needs) NeedNotice(store, need),
          UiButton('Save rule', expand: true, onPressed: _save),
        ],
      ),
    );
  }
}
