import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Hive, HiveX;
import 'package:hooks_riverpod/hooks_riverpod.dart' show ProviderScope;
import 'package:window_manager/window_manager.dart'
    show WindowOptions, windowManager;

import 'src/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    minimumSize: Size(1280, 720),
    title: 'TTS Mod Vault 1.2.0-dev',
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

  await Hive.initFlutter('TTS Mod Vault');
  runApp(ProviderScope(child: App()));
}
