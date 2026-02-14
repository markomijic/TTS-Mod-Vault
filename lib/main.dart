import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' show dotenv;
import 'package:hive_ce_flutter/hive_flutter.dart' show Hive, HiveX;
import 'package:hooks_riverpod/hooks_riverpod.dart' show ProviderScope;
import 'package:window_manager/window_manager.dart'
    show WindowOptions, windowManager;

import 'src/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Hive.initFlutter('TTS Mod Vault-beta');

  WindowOptions windowOptions = const WindowOptions(
    minimumSize: Size(854, 480),
    title: 'TTS Mod Vault 1.4.0-beta5',
    center: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(ProviderScope(child: App()));
}
