// Teleponter: teleprompter libre para Windows y Android.
// Basado en Textream (https://github.com/f/textream), MIT License,
// Copyright (c) 2026 Fatih Kadir Akin.

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'core/settings.dart';
import 'services/window_service.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowService.init();
  final settings = await AppSettings.load();
  final state = AppState(settings);
  runApp(AppScope(state: state, child: const TeleponterApp()));
}

class TeleponterApp extends StatelessWidget {
  const TeleponterApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF30D158);
    return MaterialApp(
      title: 'Teleponter',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E0E10),
        useMaterial3: true,
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
