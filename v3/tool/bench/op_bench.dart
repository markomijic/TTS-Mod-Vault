// Headless operation benchmark (docs/v3-rewrite-plan.md, section 10.3):
// bootstraps the application layer in a `ProviderContainer` without any
// widget, runs one scenario against a sandbox library and reports its wall
// time and peak RSS.
//
// The provider layer imports `hooks_riverpod` (and through it Flutter), so
// a plain `dart run` cannot load this file (`dart:ui` is not available on
// the stand-alone VM). It runs inside the headless Flutter test engine
// instead, which has `dart:ui` but creates no window and needs no
// `WidgetsFlutterBinding`:
//
//   flutter test tool/bench/op_bench.dart --reporter expanded \
//       --dart-define=OPB_LIBRARY=D:\tmp\ttsmv-bench\sandbox \
//       --dart-define=OPB_DATA=D:\tmp\ttsmv-bench\data \
//       --dart-define=OPB_SCENARIO=backup-one --dart-define=OPB_MOD=3781830124 \
//       --dart-define=OPB_BACKUPS=D:\tmp\ttsmv-bench\backups
//
// Every option is read from a `--dart-define=OPB_<NAME>=<value>` or, when
// absent, from the environment variable of the same name; `op_bench.ps1`
// next to this file turns ordinary switches into those. Options:
//
//   OPB_LIBRARY      the TTS folder (contains Mods/ and Saves/)      required
//   OPB_DATA         folder for vault.sqlite and vault.log           required
//   OPB_SCENARIO     refresh | backup-one | backup-all | import |
//                    cleanup | check-urls                            required
//   OPB_BACKUPS      backups folder (backup-one, backup-all; also
//                    indexed by the refresh when given)
//   OPB_TTSMOD       archive to import (import)
//   OPB_MOD          mod id (backup-one; default: the mod with the most
//                    assets)
//   OPB_CONCURRENCY  URL check / download concurrency (default 5)
//   OPB_COLD         1: delete the database before the run
//   OPB_DRY_RUN      1: cleanup only scans
//   OPB_JSON         1: print the result as one JSON line
//   OPB_OUT          file the JSON result is also written to
//   OPB_WORKERS      worker pool size (default: processors - 2)
//
// The Dart API (`runScenario`) is what `test/tool/op_bench_test.dart`
// exercises; `main` is the CLI shell around it.
//
// Safety (plan 10.2): the data folder and the backups folder may never lie
// inside the user's Documents folder, and `import` and a non-dry-run
// `cleanup` refuse a library inside it (they write into the library). The
// read-only scenarios accept the real library and say so loudly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:flutter_test/flutter_test.dart' show Timeout, test;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart'
    show keyValueStoreProvider;
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/workers/worker_pool.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/drift_key_value_store.dart';
import 'package:tts_mod_vault/data/legacy/hive_settings_importer.dart'
    show legacyImporterProvider;
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/application/backup_operations.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_operation.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_operations.dart';
import 'package:tts_mod_vault/features/cleanup/application/cleanup_service.dart';
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

/// The scenarios of plan 10.3 this tool can run.
enum BenchScenario {
  /// One library refresh (cold with `cold: true`, warm otherwise).
  refresh('refresh'),

  /// `CreateBackupOperation` for one mod.
  backupOne('backup-one'),

  /// `BulkBackupOperation` (replace behaviour) over every mod.
  backupAll('backup-all'),

  /// `ImportBackupOperation` of one `.ttsmod`, answering `useBackup`.
  import('import'),

  /// `CleanupService.scanOrphans` then `deleteCandidates`.
  cleanup('cleanup'),

  /// `BulkCheckUrlsOperation` over every mod (real network).
  checkUrls('check-urls');

  const BenchScenario(this.cliName);

  /// The name on the command line.
  final String cliName;

  /// Parses a CLI name; throws [ArgumentError] for unknown names.
  static BenchScenario parse(String name) => values.firstWhere(
    (s) => s.cliName == name,
    orElse: () => throw ArgumentError.value(
      name,
      'scenario',
      'expected one of ${[for (final s in values) s.cliName].join(', ')}',
    ),
  );
}

/// What to run.
final class ScenarioRequest {
  /// Creates a request.
  const ScenarioRequest({
    required this.libraryDir,
    required this.dataDir,
    required this.scenario,
    this.backupsDir,
    this.ttsmodPath,
    this.modId,
    this.concurrency,
    this.cold = false,
    this.dryRun = false,
    this.workerPoolSize,
  });

  /// The TTS folder (contains `Mods/` and `Saves/`).
  final String libraryDir;

  /// Folder for `vault.sqlite` and `vault.log`.
  final String dataDir;

  /// The scenario.
  final BenchScenario scenario;

  /// Backups folder; required by the backup scenarios, indexed by the
  /// refresh whenever given.
  final String? backupsDir;

  /// Archive to import.
  final String? ttsmodPath;

  /// Mod id for [BenchScenario.backupOne]; null picks the mod with the most
  /// assets.
  final String? modId;

  /// Concurrency of the URL check; null keeps the stored / default value.
  final int? concurrency;

  /// Delete the database before the run.
  final bool cold;

  /// Cleanup: scan only.
  final bool dryRun;

  /// Worker pool size; null for the app's default.
  final int? workerPoolSize;

  /// `Mods/`.
  String get modsDir => p.join(libraryDir, ttsModsFolder);

  /// `Saves/`.
  String get savesDir => p.join(libraryDir, ttsSavesFolder);
}

/// RSS of this process around the measured operation.
final class MemoryStats {
  /// Creates the stats.
  const MemoryStats({
    required this.baselineRss,
    required this.peakRss,
    required this.samples,
    required this.maxRssAtEnd,
  });

  /// `ProcessInfo.currentRss` right before the operation.
  final int baselineRss;

  /// Highest `ProcessInfo.currentRss` seen during the operation (sampled
  /// every 50 ms on a timer, so a shorter spike can be missed).
  final int peakRss;

  /// Number of samples taken.
  final int samples;

  /// `ProcessInfo.maxRss` after the operation (the OS-tracked peak of the
  /// whole process, including the setup refresh).
  final int maxRssAtEnd;

  /// `peakRss - baselineRss`.
  int get peakDelta => peakRss - baselineRss;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'baselineRssBytes': baselineRss,
    'peakRssBytes': peakRss,
    'peakDeltaBytes': peakDelta,
    'samples': samples,
    'maxRssAtEndBytes': maxRssAtEnd,
  };
}

/// What a scenario produced.
final class ScenarioResult {
  /// Creates a result.
  const ScenarioResult({
    required this.scenario,
    required this.libraryDir,
    required this.dataDir,
    required this.elapsedMs,
    required this.setupRefreshMs,
    required this.memory,
    required this.details,
    required this.warnings,
  });

  /// The scenario.
  final BenchScenario scenario;

  /// The library it ran against.
  final String libraryDir;

  /// The data folder it used.
  final String dataDir;

  /// Wall time of the measured operation.
  final int elapsedMs;

  /// Wall time of the refresh that loaded the library first; null for
  /// [BenchScenario.refresh] (there the refresh is the operation).
  final int? setupRefreshMs;

  /// RSS around the operation.
  final MemoryStats memory;

  /// Scenario-specific counts (`durationMs` and the phase splits for a
  /// refresh, archive size for a backup, ...).
  final Map<String, Object?> details;

  /// Non-fatal notes (the library was the real one, HTTP overrides were
  /// removed, ...).
  final List<String> warnings;

  /// JSON form (one object; what `OPB_JSON=1` prints).
  Map<String, Object?> toJson() => {
    'scenario': scenario.cliName,
    'library': libraryDir,
    'data': dataDir,
    'elapsedMs': elapsedMs,
    'setupRefreshMs': setupRefreshMs,
    'memory': memory.toJson(),
    'details': details,
    'warnings': warnings,
    'jit': true,
    'host': Platform.environment['FLUTTER_TEST'] == 'true'
        ? 'flutter_tester'
        : 'dart',
  };
}

/// Banner printed before every run.
const String timingBanner =
    'NOTE: this runs on the JIT (flutter_tester / dart run); absolute '
    'timings are NOT release numbers. Compare the memory shape (flat vs. '
    'proportional to archive size) and relative timings between scenarios '
    'and library sizes only.';

/// The roots the data and backups folders must never lie in.
List<String> documentsRoots() {
  final env = Platform.environment;
  final homes = <String>{?env['USERPROFILE'], ?env['HOME']};
  return [for (final home in homes) p.join(home, 'Documents')];
}

bool _isInside(String path, String root) {
  final a = p.normalize(p.absolute(path)).toLowerCase();
  final b = p.normalize(p.absolute(root)).toLowerCase();
  return a == b || p.isWithin(b, a);
}

/// Enforces plan 10.2 for [req]; returns the warnings to attach. Throws
/// [ArgumentError] on a refused combination.
List<String> checkSafety(ScenarioRequest req, {List<String>? forbiddenRoots}) {
  final roots = forbiddenRoots ?? documentsRoots();
  final warnings = <String>[];
  for (final root in roots) {
    if (_isInside(req.dataDir, root)) {
      throw ArgumentError.value(
        req.dataDir,
        'dataDir',
        'must not be inside $root',
      );
    }
    final backups = req.backupsDir;
    if (backups != null && _isInside(backups, root)) {
      throw ArgumentError.value(
        backups,
        'backupsDir',
        'must not be inside $root (plan 10.2: backups go to the scratch folder)',
      );
    }
    if (_isInside(req.libraryDir, root)) {
      final writes =
          req.scenario == BenchScenario.import ||
          (req.scenario == BenchScenario.cleanup && !req.dryRun);
      if (writes) {
        throw ArgumentError.value(
          req.libraryDir,
          'libraryDir',
          '${req.scenario.cliName} writes into the library; a library '
              'inside $root is read-only (plan 10.2). Use a sandbox copy.',
        );
      }
      warnings.add(
        'The library is inside $root (the real one?): this scenario only '
        'reads it, but double-check before going on.',
      );
    }
  }
  if ((req.scenario == BenchScenario.backupOne ||
          req.scenario == BenchScenario.backupAll) &&
      (req.backupsDir == null || req.backupsDir!.isEmpty)) {
    throw ArgumentError.value(
      req.backupsDir,
      'backupsDir',
      'required for ${req.scenario.cliName}',
    );
  }
  if (req.scenario == BenchScenario.import &&
      (req.ttsmodPath == null || req.ttsmodPath!.isEmpty)) {
    throw ArgumentError.value(req.ttsmodPath, 'ttsmodPath', 'required');
  }
  return warnings;
}

/// A [DirectoriesController] that answers with fixed folders instead of
/// reading them from the store.
final class _FixedDirectoriesController extends DirectoriesController {
  _FixedDirectoriesController(this._directories);

  final Directories _directories;

  @override
  Future<Directories> build() async => _directories;
}

/// Exposes a `Ref` so the operations (which take one) can be built from a
/// bare container.
final _refProvider = Provider<Ref>((ref) => ref);

/// Samples `ProcessInfo.currentRss` on a timer.
final class _RssSampler {
  final List<int> _samples = [];
  Timer? _timer;
  int _baseline = 0;

  void start() {
    _baseline = ProcessInfo.currentRss;
    _samples.add(_baseline);
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _samples.add(ProcessInfo.currentRss);
    });
  }

  MemoryStats stop() {
    _timer?.cancel();
    _timer = null;
    _samples.add(ProcessInfo.currentRss);
    return MemoryStats(
      baselineRss: _baseline,
      peakRss: _samples.reduce(max),
      samples: _samples.length,
      maxRssAtEnd: ProcessInfo.maxRss,
    );
  }
}

/// Runs [req] and returns the measurements. [log] receives progress lines.
Future<ScenarioResult> runScenario(
  ScenarioRequest req, {
  void Function(String line)? log,
  List<String>? forbiddenRoots,
}) async {
  void say(String line) => log?.call(line);
  final warnings = checkSafety(req, forbiddenRoots: forbiddenRoots);
  for (final warning in warnings) {
    say('warning: $warning');
  }

  final dataDir = Directory(req.dataDir);
  await dataDir.create(recursive: true);
  final dbFile = File(p.join(req.dataDir, 'vault.sqlite'));
  if (req.cold) {
    for (final f in [
      dbFile,
      File('${dbFile.path}-wal'),
      File('${dbFile.path}-shm'),
    ]) {
      if (f.existsSync()) {
        say('cold: deleting ${p.basename(f.path)}');
        f.deleteSync();
      }
    }
  }

  final db = AppDatabase.open(dbFile);
  final kv = DriftKeyValueStore(db);
  final appLog = AppLog(
    store: LogStore(),
    sinks: [RotatingFileLogSink(directory: req.dataDir)],
  );
  final directories = Directories(
    modsDir: req.modsDir,
    savesDir: req.savesDir,
    backupsDir: req.backupsDir ?? '',
  );
  final poolSize = req.workerPoolSize;
  final container = ProviderContainer(
    // As in main.dart: a failed scan or download must surface, not re-run.
    retry: (retryCount, error) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      keyValueStoreProvider.overrideWithValue(kv),
      appLogProvider.overrideWithValue(appLog),
      legacyImporterProvider.overrideWithValue(null),
      directoriesProvider.overrideWith(
        () => _FixedDirectoriesController(directories),
      ),
      if (poolSize != null)
        workerPoolProvider.overrideWith((ref) {
          final pool = WorkerPool(size: poolSize, debugName: 'bench-workers');
          ref.onDispose(pool.dispose);
          return pool;
        }),
    ],
  );

  try {
    appLog.info(
      LogSource.app,
      'op_bench ${req.scenario.cliName} started',
      details: 'library: ${req.libraryDir}, data: ${req.dataDir}',
    );
    final concurrency = req.concurrency;
    if (concurrency != null) {
      await container
          .read(networkOptionsProvider.notifier)
          .set(NetworkOptions(concurrentDownloads: concurrency));
    }

    int? setupRefreshMs;
    if (req.scenario != BenchScenario.refresh) {
      say('loading the library (setup refresh)...');
      final sw = Stopwatch()..start();
      await _refresh(container);
      setupRefreshMs = sw.elapsedMilliseconds;
      final state = container.read(libraryControllerProvider).requireValue;
      say(
        'library loaded in $setupRefreshMs ms: ${state.mods.length} mods, '
        '${state.saves.length} saves, ${state.backups.length} backups',
      );
    }

    say('running ${req.scenario.cliName}...');
    final sampler = _RssSampler()..start();
    final sw = Stopwatch()..start();
    final details = await switch (req.scenario) {
      BenchScenario.refresh => _runRefresh(container),
      BenchScenario.backupOne => _runBackupOne(container, req, say),
      BenchScenario.backupAll => _runBackupAll(container, req),
      BenchScenario.import => _runImport(container, req),
      BenchScenario.cleanup => _runCleanup(container, req, say),
      BenchScenario.checkUrls => _runCheckUrls(container, req, warnings, say),
    };
    sw.stop();
    final memory = sampler.stop();
    appLog.info(
      LogSource.app,
      'op_bench ${req.scenario.cliName} finished in ${sw.elapsedMilliseconds} ms',
      details: jsonEncode(details),
    );
    return ScenarioResult(
      scenario: req.scenario,
      libraryDir: p.normalize(p.absolute(req.libraryDir)),
      dataDir: p.normalize(p.absolute(req.dataDir)),
      elapsedMs: sw.elapsedMilliseconds,
      setupRefreshMs: setupRefreshMs,
      memory: memory,
      details: details,
      warnings: warnings,
    );
  } finally {
    await appLog.flush();
    final pool = container.read(workerPoolProvider);
    container.dispose();
    await pool.dispose();
    await db.close();
    await appLog.dispose();
  }
}

Future<void> _refresh(ProviderContainer container) async {
  final store = container.read(appLogProvider).store;
  final before = store.length;
  await container.read(libraryControllerProvider.notifier).refresh();
  final state = container.read(libraryControllerProvider);
  if (state.hasError) {
    Error.throwWithStackTrace(state.error!, state.stackTrace!);
  }
  // The controller checkpoints the WAL after publishing the state without
  // awaiting it; let that finish so closing the database cannot race it.
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final entries = store.entries;
    if (entries
        .skip(before)
        .any((e) => e.message.startsWith('WAL checkpoint after refresh'))) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// The `key=value` numbers of the last `Library refresh finished` line.
Map<String, Object?> _lastRefreshCounts(ProviderContainer container) {
  final entries = container.read(appLogProvider).store.entries;
  final entry = entries.lastWhere(
    (e) => e.message.startsWith(libraryRefreshFinishedPrefix),
  );
  final counts = <String, Object?>{};
  for (final part in entry.message.split(' ')) {
    final separator = part.indexOf('=');
    if (separator <= 0) continue;
    final value = int.tryParse(part.substring(separator + 1));
    if (value != null) counts[part.substring(0, separator)] = value;
  }
  return counts;
}

Future<Map<String, Object?>> _runRefresh(ProviderContainer container) async {
  await _refresh(container);
  final state = container.read(libraryControllerProvider).requireValue;
  return {
    ..._lastRefreshCounts(container),
    'modsInState': state.mods.length,
    'savesInState': state.saves.length,
    'backupsInState': state.backups.length,
    'stateWarnings': state.warnings.length,
  };
}

Mod _pickMod(ProviderContainer container, String? modId) {
  final state = container.read(libraryControllerProvider).requireValue;
  if (state.all.isEmpty) throw StateError('the library has no mods');
  if (modId != null && modId.isNotEmpty) {
    return state.all.firstWhere(
      (m) => m.id == modId,
      orElse: () =>
          throw ArgumentError.value(modId, 'mod', 'not in the library'),
    );
  }
  return state.all.reduce((a, b) => b.summary.total > a.summary.total ? b : a);
}

Future<Map<String, Object?>> _runBackupOne(
  ProviderContainer container,
  ScenarioRequest req,
  void Function(String) say,
) async {
  final mod = _pickMod(container, req.modId);
  say(
    'backing up "${mod.displayName}" (${mod.id}, ${mod.summary.present}/'
    '${mod.summary.total} assets present)',
  );
  final result = await container
      .read(operationRunnerProvider.notifier)
      .run(
        CreateBackupOperation(
          ref: container.read(_refProvider),
          mod: mod,
          targetDir: req.backupsDir!,
        ),
      );
  return {
    'modId': mod.id,
    'modName': mod.displayName,
    'modJsonBytes': mod.sizeBytes,
    'assetsPresent': mod.summary.present,
    'assetsTotal': mod.summary.total,
    'archive': result.backup.path,
    'archiveBytes': result.backup.sizeBytes,
    'assetCount': result.assetCount,
    'skipped': result.skipped,
  };
}

Future<Map<String, Object?>> _runBackupAll(
  ProviderContainer container,
  ScenarioRequest req,
) async {
  final state = container.read(libraryControllerProvider).requireValue;
  final result = await container
      .read(operationRunnerProvider.notifier)
      .run(
        BulkBackupOperation(
          ref: container.read(_refProvider),
          mods: state.mods,
          folder: req.backupsDir!,
          behavior: BulkBackupBehavior.replace,
        ),
      );
  var bytes = 0;
  for (final outcome in result.outcomes) {
    bytes += outcome.value?.backup?.backup.sizeBytes ?? 0;
  }
  return {
    'mods': state.mods.length,
    'backedUp': result.backedUp,
    'skipped': result.skipped,
    'modsFailed': result.modsFailed,
    'archiveBytes': bytes,
    'cancelled': result.cancelled,
  };
}

Future<Map<String, Object?>> _runImport(
  ProviderContainer container,
  ScenarioRequest req,
) async {
  final archive = File(req.ttsmodPath!);
  if (!archive.existsSync()) {
    throw ArgumentError.value(req.ttsmodPath, 'ttsmod', 'not found');
  }
  final result = await container
      .read(operationRunnerProvider.notifier)
      .run(
        ImportBackupOperation(
          ref: container.read(_refProvider),
          ttsmodPath: archive.path,
          onJsonConflict: (_) async => JsonConflictChoice.useBackup,
        ),
      );
  return {
    'archive': archive.path,
    'archiveBytes': archive.lengthSync(),
    'jsonPath': result.jsonPath,
    'assetsExtracted': result.assetsExtracted,
    'failed': result.failed,
    'jsonSkipped': result.jsonSkipped,
    'cancelled': result.cancelled,
  };
}

Future<Map<String, Object?>> _runCleanup(
  ProviderContainer container,
  ScenarioRequest req,
  void Function(String) say,
) async {
  final service = container.read(cleanupServiceProvider);
  final scanWatch = Stopwatch()..start();
  final scan = await service.scanOrphans();
  scanWatch.stop();
  say(
    'cleanup scan: ${scan.candidates.length} candidate(s), '
    '${scan.totalBytes} bytes, ${scan.warnings.length} warning(s) in '
    '${scanWatch.elapsedMilliseconds} ms',
  );
  final details = <String, Object?>{
    'scanMs': scanWatch.elapsedMilliseconds,
    'candidates': scan.candidates.length,
    'candidateBytes': scan.totalBytes,
    'scanWarnings': scan.warnings.length,
    'dryRun': req.dryRun,
  };
  if (req.dryRun) return details;
  final deleteWatch = Stopwatch()..start();
  final result = await service.deleteCandidates(scan.candidates);
  deleteWatch.stop();
  say(
    'cleanup delete: ${result.deleted} deleted, ${result.failed} failed, '
    '${result.bytesFreed} bytes in ${deleteWatch.elapsedMilliseconds} ms',
  );
  return {
    ...details,
    'deleteMs': deleteWatch.elapsedMilliseconds,
    'deleted': result.deleted,
    'deleteFailed': result.failed,
    'bytesFreed': result.bytesFreed,
  };
}

Future<Map<String, Object?>> _runCheckUrls(
  ProviderContainer container,
  ScenarioRequest req,
  List<String> warnings,
  void Function(String) say,
) async {
  // A Flutter test binding (not created here, but harmless to check)
  // replaces HttpClient with one that answers 400 to everything.
  if (HttpOverrides.current != null) {
    HttpOverrides.global = null;
    warnings.add('HttpOverrides were installed and have been removed');
  }
  final state = container.read(libraryControllerProvider).requireValue;
  final options = await container
      .read(networkOptionsProvider.notifier)
      .ensureLoaded();
  say(
    'checking the URLs of ${state.mods.length} mod(s) with '
    '${options.concurrentDownloads} worker(s)...',
  );
  final result = await container
      .read(operationRunnerProvider.notifier)
      .run(
        BulkCheckUrlsOperation(
          ref: container.read(_refProvider),
          mods: state.mods,
        ),
      );
  var checked = 0;
  var total = 0;
  for (final outcome in result.outcomes) {
    checked += outcome.value?.checked ?? 0;
    total += outcome.value?.total ?? 0;
  }
  return {
    'mods': state.mods.length,
    'modsChecked': result.modsChecked,
    'modsFailed': result.modsFailed,
    'urlsChecked': checked,
    'urlsTotal': total,
    'invalidUrls': result.invalidUrlCount,
    'concurrency': options.concurrentDownloads,
    'cancelled': result.cancelled,
  };
}

// --- CLI shell --------------------------------------------------------------

// Options come from `--dart-define=OPB_<NAME>=...` first and the environment
// variable `OPB_<NAME>` second. `String.fromEnvironment` needs a constant
// key, so every define is listed here.
const _optionKeys = {
  'LIBRARY': String.fromEnvironment('OPB_LIBRARY'),
  'DATA': String.fromEnvironment('OPB_DATA'),
  'SCENARIO': String.fromEnvironment('OPB_SCENARIO'),
  'BACKUPS': String.fromEnvironment('OPB_BACKUPS'),
  'TTSMOD': String.fromEnvironment('OPB_TTSMOD'),
  'MOD': String.fromEnvironment('OPB_MOD'),
  'CONCURRENCY': String.fromEnvironment('OPB_CONCURRENCY'),
  'COLD': String.fromEnvironment('OPB_COLD'),
  'DRY_RUN': String.fromEnvironment('OPB_DRY_RUN'),
  'JSON': String.fromEnvironment('OPB_JSON'),
  'OUT': String.fromEnvironment('OPB_OUT'),
  'WORKERS': String.fromEnvironment('OPB_WORKERS'),
};

String? _read(String name) {
  final defined = _optionKeys[name] ?? '';
  if (defined.isNotEmpty) return defined;
  final env = Platform.environment['OPB_$name'];
  return env == null || env.isEmpty ? null : env;
}

bool _flag(String name) {
  final value = _read(name)?.toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
}

ScenarioRequest _requestFromOptions() {
  final library = _read('LIBRARY');
  final data = _read('DATA');
  final scenario = _read('SCENARIO');
  if (library == null || data == null || scenario == null) {
    throw ArgumentError(
      'OPB_LIBRARY, OPB_DATA and OPB_SCENARIO are required (see the header '
      'of tool/bench/op_bench.dart or use tool/bench/op_bench.ps1)',
    );
  }
  final concurrency = _read('CONCURRENCY');
  final workers = _read('WORKERS');
  return ScenarioRequest(
    libraryDir: library,
    dataDir: data,
    scenario: BenchScenario.parse(scenario),
    backupsDir: _read('BACKUPS'),
    ttsmodPath: _read('TTSMOD'),
    modId: _read('MOD'),
    concurrency: concurrency == null ? null : int.parse(concurrency),
    cold: _flag('COLD'),
    dryRun: _flag('DRY_RUN'),
    workerPoolSize: workers == null ? null : int.parse(workers),
  );
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

Future<void> _runCli() async {
  final req = _requestFromOptions();
  stdout
    ..writeln(timingBanner)
    ..writeln(
      'op_bench: scenario=${req.scenario.cliName} library=${req.libraryDir} '
      'data=${req.dataDir}'
      '${req.backupsDir == null ? '' : ' backups=${req.backupsDir}'}'
      '${req.ttsmodPath == null ? '' : ' ttsmod=${req.ttsmodPath}'}'
      '${req.modId == null ? '' : ' mod=${req.modId}'}'
      '${req.cold ? ' cold' : ''}${req.dryRun ? ' dry-run' : ''}',
    );
  final result = await runScenario(
    req,
    log: (line) => stdout.writeln('  $line'),
  );
  stdout
    ..writeln('result: ${req.scenario.cliName}')
    ..writeln('  elapsed        : ${result.elapsedMs} ms')
    ..writeln(
      '  setup refresh  : '
      '${result.setupRefreshMs == null ? 'n/a' : '${result.setupRefreshMs} ms'}',
    )
    ..writeln(
      '  rss baseline   : ${_mb(result.memory.baselineRss)} MB   '
      'peak ${_mb(result.memory.peakRss)} MB   '
      'delta ${_mb(result.memory.peakDelta)} MB   '
      '(${result.memory.samples} samples, 50 ms)',
    )
    ..writeln('  maxRss at end  : ${_mb(result.memory.maxRssAtEnd)} MB');
  for (final entry in result.details.entries) {
    stdout.writeln('  ${entry.key.padRight(15)}: ${entry.value}');
  }
  for (final warning in result.warnings) {
    stdout.writeln('  warning: $warning');
  }
  final json = jsonEncode(result.toJson());
  if (_flag('JSON')) stdout.writeln(json);
  final out = _read('OUT');
  if (out != null) {
    await File(out).writeAsString('$json\n');
    stdout.writeln('  json written to $out');
  }
}

/// Entry point. Under `flutter test` (the only host that can load this
/// file) the work is wrapped in one test with no timeout; `main` takes no
/// arguments because the test runner refuses a `main(List<String>)`.
void main() {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    test('op_bench', _runCli, timeout: Timeout.none);
  } else {
    unawaited(_runCli());
  }
}
