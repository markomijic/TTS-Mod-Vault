import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:file/local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;
import 'package:pdfrx_engine/pdfrx_engine.dart' show Pdfrx, pdfrxInitialize;
import 'package:tts_mod_vault/bootstrap/app_paths.dart';
import 'package:tts_mod_vault/bootstrap/startup_timeline.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/drift_key_value_store.dart';
import 'package:tts_mod_vault/data/legacy/hive_settings_importer.dart';
import 'package:window_manager/window_manager.dart'
    show WindowOptions, windowManager;

/// Everything `main()` needs after [bootstrap] has run.
final class BootstrapResult {
  const BootstrapResult({
    required this.db,
    required this.kv,
    required this.log,
    required this.dataDir,
    required this.legacyImporter,
  });

  final AppDatabase db;
  final KeyValueStore kv;

  /// Structured log with a rotating file sink at `<dataDir>/vault.log`.
  final AppLog log;

  /// Directory holding `vault.sqlite` and `vault.log` (see [AppPaths]).
  final String dataDir;

  /// Reads (and later deletes) the 2.x Hive settings from the Documents
  /// folder on first run; null when the folder could not be resolved.
  final LegacySettingsImporter? legacyImporter;
}

/// Process-level start-up that must happen before `runApp`: bindings, window
/// manager, pdfium, the database and the window itself.
///
/// Every step's duration is recorded on [timeline] and logged as one
/// `Bootstrap finished` line so the start-up cost stays visible.
Future<BootstrapResult> bootstrap({StartupTimeline? timeline}) async {
  final clock = timeline ?? StartupTimeline();
  final startMs = clock.elapsedMs;
  final splits = <String, int>{};
  var last = startMs;
  void split(String name) {
    final now = clock.elapsedMs;
    splits[name] = now - last;
    last = now;
  }

  WidgetsFlutterBinding.ensureInitialized();
  split('binding');
  await windowManager.ensureInitialized();
  split('windowManager');
  _configurePdfiumModulePath();
  await pdfrxInitialize();
  split('pdfium');

  final paths = await AppPaths.resolve();
  await paths.ensureExists();
  split('paths');
  final db = AppDatabase.open(File(paths.databaseFile));
  split('dbOpen');
  final kv = DriftKeyValueStore(db);
  final log = AppLog(
    store: LogStore(),
    sinks: [RotatingFileLogSink(directory: paths.dataDir)],
  );
  split('kv');

  final info = await PackageInfo.fromPlatform();
  split('packageInfo');
  final windowOptions = WindowOptions(
    minimumSize: const Size(854, 480),
    title: 'TTS Mod Vault ${info.version}',
    center: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  split('windowShow');

  // v2 maximised from the splash page's post-frame callback; same timing here.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_maximizeOnFirstShow());
  });

  log.info(
    LogSource.app,
    'TTS Mod Vault ${info.version} started',
    details: 'data directory: ${paths.dataDir}',
  );
  log.info(
    LogSource.app,
    'Bootstrap finished: '
    '${[for (final e in splits.entries) '${e.key}Ms=${e.value}'].join(' ')} '
    'totalMs=${clock.elapsedMs - startMs} sinceMainMs=${clock.elapsedMs}',
  );

  LegacySettingsImporter? legacyImporter;
  try {
    final documents = await getApplicationDocumentsDirectory();
    legacyImporter = HiveSettingsImporter(
      fs: const LocalFileSystem(),
      documentsDir: documents.path,
    );
  } on Object catch (error) {
    log.warning(
      LogSource.app,
      'Could not resolve the Documents folder; skipping the 2.x settings import',
      details: '$error',
    );
  }

  return BootstrapResult(
    db: db,
    kv: kv,
    log: log,
    dataDir: paths.dataDir,
    legacyImporter: legacyImporter,
  );
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
