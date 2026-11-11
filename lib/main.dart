import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import 'rules/rules_store.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(QuietlyApp(store: RulesStore()));
}

class QuietlyApp extends StatelessWidget {
  const QuietlyApp({super.key, required this.store});

  final RulesStore store;

  @override
  Widget build(BuildContext context) {
    return UiApp(
      title: 'Quietly',
      home: HomeScreen(store: store),
    );
  }
}
