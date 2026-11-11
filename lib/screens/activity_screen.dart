import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../rules/rules_platform.dart';
import '../rules/rules_store.dart';

/// The last 50 times a rule started or stopped.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.store});

  final RulesStore store;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<ActivityEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await widget.store.platform.log();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _clear() async {
    final ok = await UiDialog.confirm(
      context,
      title: 'Clear the activity log?',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok) return;
    await widget.store.platform.clearLog();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return UiScaffold(
      appBar: UiAppBar(
        title: 'Activity',
        actions: [
          if (entries != null && entries.isNotEmpty)
            UiIconButton(Icons.delete_sweep_rounded, tooltip: 'Clear log', onPressed: _clear),
        ],
      ),
      scrollable: true,
      onRefresh: _load,
      body: _body(entries),
    );
  }

  Widget _body(List<ActivityEntry>? entries) {
    if (entries == null) return const Center(child: UiSpinner(size: 28));
    if (entries.isEmpty) {
      return const UiEmptyState(
        icon: Icons.history_rounded,
        title: 'Nothing yet',
        message: 'When a rule starts or stops, it shows up here.',
      );
    }
    return UiListGroup(
      footer: 'The last ${entries.length} changes, newest first.',
      children: [
        for (final e in entries)
          UiListTile(
            e.rule,
            subtitle: e.active ? 'Started' : 'Stopped',
            icon: e.active ? Icons.play_arrow_rounded : Icons.stop_rounded,
            iconStatus: e.active ? UiStatus.success : UiStatus.neutral,
            value: _when(e.time),
          ),
      ],
    );
  }

  String _when(DateTime t) {
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? hm : '${UiFormat.relativeTime(t)} $hm';
  }
}
