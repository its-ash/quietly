import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../rules/needs.dart';
import '../rules/rules_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  final RulesStore store;

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: const UiAppBar(title: 'Settings'),
      scrollable: true,
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final status = store.status;
          if (status == null) return const Center(child: UiSpinner());
          return UiColumn(
            gap: UiSpace.lg,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiListGroup(
                header: 'Permissions',
                footer: 'Each one is only needed for the rules that use it. Tap a row to change it.',
                children: [
                  for (final need in Need.values)
                    UiListTile(
                      need.title,
                      subtitle: status.has(need) ? null : need.why,
                      icon: need.icon,
                      iconStatus: status.has(need) ? UiStatus.success : UiStatus.warning,
                      maxSubtitleLines: 3,
                      trailing: UiStatusPill(
                        status.has(need) ? 'Allowed' : 'Off',
                        status: status.has(need) ? UiStatus.success : UiStatus.warning,
                      ),
                      onTap: () => store.platform.openPermission(need),
                    ),
                ],
              ),
              if (status.tileSupported)
                UiListGroup(
                  header: 'Quick Settings',
                  children: [
                    UiListTile(
                      'Add Quick Settings tile',
                      subtitle: 'Pause and resume all rules from the notification shade.',
                      icon: Icons.dashboard_customize_rounded,
                      chevron: true,
                      onTap: () async {
                        final added = await store.platform.addTile();
                        if (context.mounted && added) context.showToast('Tile added.', status: UiStatus.success);
                      },
                    ),
                  ],
                ),
              const UiAppearanceSection(),
              const UiUpdateSection(storeId: 'quietly'),
              const UiDeveloperSection(),
            ],
          );
        },
      ),
    );
  }
}
