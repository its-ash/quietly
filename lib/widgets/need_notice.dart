import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../rules/needs.dart';
import '../rules/rules_store.dart';

/// A warning with an "Allow" button, shown only while [need] is not granted.
/// Put it next to the setting that needs it, so permissions are asked in context.
class NeedNotice extends StatelessWidget {
  const NeedNotice(this.store, this.need, {super.key});

  final RulesStore store;
  final Need need;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final status = store.status;
        if (status == null || status.has(need)) return const SizedBox.shrink();
        return UiAlert(
          need.why,
          title: need.title,
          status: UiStatus.warning,
          icon: need.icon,
          action: UiButton(
            'Allow',
            size: UiSize.sm,
            variant: UiButtonVariant.soft,
            onPressed: () => store.platform.openPermission(need),
          ),
        );
      },
    );
  }
}
