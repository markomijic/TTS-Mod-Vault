import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' show Pdfrx, pdfrxInitialize;
import 'package:tts_mod_vault/bootstrap/app_paths.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/drift_key_value_store.dart';
import 'package:window_manager/window_manager.dart'
    show WindowOptions, windowManager;

/// Everything `main()` needs after [bootstrap] has run.
final class BootstrapResult {
  const BootstrapResult({
    required this.db,
    required this.kv,
    required this.log,
    required this.dataDir,
  });

  final AppDatabase db;
  final KeyValueStore kv;

  /// Structured log with a rotating file sink at `<dataDir>/vault.log`.
  final AppLog log;

  /// Directory holding `vault.sqlite` and `vault.log` (see [AppPaths]).
  final String dataDir;
}

/// Process-level start-up that must happen before `runApp`: bindings, window
/// manager, pdfium, the database and the window itself.
Future<BootstrapResult> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  _configurePdfiumModulePath();
  await pdfrxInitialize();

  final paths = await AppPaths.resolve();
  await paths.ensureExists();
  final db = AppDatabase.open(File(paths.databaseFile));
  final kv = DriftKeyValueStore(db);
  final log = AppLog(
    store: LogStore(),
    sinks: [RotatingFileLogSink(directory: paths.dataDir)],
  );

  final info = await PackageInfo.fromPlatform();
  final windowOptions = WindowOptions(
    minimumSize: const Size(854, 480),
    title: 'TTS Mod Vault ${info.version}',
    center: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // v2 maximised from the splash page's post-frame callback; same timing here.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_maximizeOnFirstShow());
  });

  log.info(
    LogSource.app,
    'TTS Mod Vault ${info.version} started',
    details: 'data directory: ${paths.dataDir}',
  );

  return BootstrapResult(db: db, kv: kv, log: log, dataDir: paths.dataDir);
}

/// Maximises the window once after the first frame (ported from v2's
/// `SplashPage`).
Future<void> _maximizeOnFirstShow() async {
  // Small delay as a workaround for a Windows release-build issue (from v2).
  await Future<void>.delayed(const Duration(milliseconds: 100));
  try {
    if (await windowManager.isMaximizable() &&
        !await windowManager.isMaximized()) {
      await windowManager.maximize();
    }
  } on Object catch (e) {
    // No log store exists yet at this point.
    debugPrint('bootstrap: maximize on first show failed: $e');
  }
}

/// Points pdfrx at the pdfium dynamic library bundled with the app.
///
/// `pdfrx_engine` delivers pdfium as a Dart native asset, which on macOS ends
/// up as `Contents/Frameworks/pdfium.framework` inside the `.app`. The default
/// Dart `pdfrxInitialize()` never sets a module path, so on macOS pdfium_dart
/// falls back to `DynamicLibrary.process()` — it assumes pdfium is already
/// linked into the process. That assumption holds for JIT/debug (`flutter run`
/// preloads native-asset libraries) but not for AOT/release builds, where the
/// bundled framework is present but never loaded. The result is the downloaded
/// release dying at startup with `Failed to lookup symbol 'FPDF_InitLibrary'`.
///
/// Setting [Pdfrx.pdfiumModulePath] to the bundled framework forces
/// `DynamicLibrary.open()` on that exact path, which loads pdfium correctly in
/// both debug and release. The path is propagated to pdfrx's worker isolate.
void _configurePdfiumModulePath() {
  if (!Platform.isMacOS) return;

  // .../TTS Mod Vault.app/Contents/MacOS/<exe> -> .../Contents/Frameworks/...
  final macOsDir = File(Platform.resolvedExecutable).parent;
  final pdfium = '${macOsDir.parent.path}/Frameworks/pdfium.framework/pdfium';
  if (File(pdfium).existsSync()) {
    Pdfrx.pdfiumModulePath = pdfium;
  }
}
