import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show ProviderScope;
import 'package:window_manager/window_manager.dart'
    show WindowOptions, windowManager;

import 'src/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(double.infinity, double.infinity),
    minimumSize: Size(1280, 720),
    title: 'TTS Mod Vault 0.8.1',
    center: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    if (await windowManager.isMaximizable() &&
        !await windowManager.isMaximized()) {
      await windowManager.maximize();
    }
  });

  runApp(ProviderScope(child: App()));
}
