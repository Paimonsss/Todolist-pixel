import 'package:flutter/material.dart';

import 'core/notifications.dart';
import 'core/sync.dart';
import 'ui/home.dart';
import 'ui/pixel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifications.init();
  await SyncService.registerBackground();
  runApp(const TugasQuestApp());
}

class TugasQuestApp extends StatelessWidget {
  const TugasQuestApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tugas Quest',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'VT323',
      colorScheme: ColorScheme.fromSeed(
        seedColor: Px.violet,
        primary: Px.ink,
        surface: Px.paper,
      ),
      scaffoldBackgroundColor: Px.bg,
    ),
    home: const HomePage(),
  );
}
