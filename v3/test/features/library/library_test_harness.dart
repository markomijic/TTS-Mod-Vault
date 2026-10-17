// Shared fixtures for the library feature tests: a temporary TTS library on
// the real file system (the worker tasks need local IO) and a
// ProviderContainer wired to an in-memory database and a two-worker pool.

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/core/workers/worker_pool.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

import '../../data/fs/zip/zip_fixtures.dart';

/// Unix seconds of a save time in late 2023; backups written "now" are newer.
const int epoch2023 = 1700000000;

/// Unix seconds in 2020, older than [epoch2023].
const int epoch2020 = 1600000000;

/// A throw-away TTS library under the system temp directory.
final class TempLibrary {
  TempLibrary._(this.root);

  /// Creates `Mods/Workshop`, `Saves`, `Saves/Saved Objects`, every asset
  /// folder and `Backups`, all empty.
  factory TempLibrary.create() {
    final root = Directory.systemTemp.createTempSync('ttsmv_library_');
    final lib = TempLibrary._(root);
    Directory(lib.workshopDir).createSync(recursive: true);
    Directory(lib.savedObjectsDir).createSync(recursive: true);
    Directory(lib.backupsDir).createSync(recursive: true);
    for (final type in AssetType.values) {
      Directory(lib.directories.assetDir(type)).createSync(recursive: true);
    }
    return lib;
  }

  /// The temp root.
  final Directory root;

  /// Folders as the app sees them.
  Directories get directories => Directories(
    modsDir: p.join(root.path, ttsModsFolder),
    savesDir: p.join(root.path, ttsSavesFolder),
    backupsDir: backupsDir,
  );

  /// `Mods/Workshop`.
  String get workshopDir => directories.workshopDir;

  /// `Saves`.
  String get savesDir => directories.savesDir;

  /// `Saves/Saved Objects`.
  String get savedObjectsDir => directories.savedObjectsDir;

  /// `Backups`.
  String get backupsDir => p.join(root.path, 'Backups');

  /// Writes a mod JSON at [relativePath] (relative to the root) and returns
  /// its normalised path. [assets] are `(jsonKey, url)` pairs.
  String writeJson(
    String relativePath, {
    required String saveName,
    int? epochTime,
    List<(String, String)> assets = const [],
  }) {
    final file = File(p.join(root.path, relativePath))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        modJson(saveName: saveName, epochTime: epochTime, assets: assets),
      );
    return p.normalize(file.path);
  }

  /// Writes a small placeholder file next to the JSON at [jsonPath] with the
  /// same basename and `.png` extension.
  String writeSiblingImage(String jsonPath) {
    final path = p.setExtension(jsonPath, '.png');
    File(path).writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);
    return p.normalize(path);
  }

  /// Writes a placeholder cached asset for [url] in the folder of [type],
  /// named like TTS names it (`fileNameFromUrl(url)` plus [extension]).
  String writeAsset(AssetType type, String url, {String extension = '.png'}) {
    final path = p.join(
      directories.assetDir(type),
      '${fileNameFromUrl(url)}$extension',
    );
    File(path).writeAsBytesSync(const [1, 2, 3]);
    return p.normalize(path);
  }

  /// Writes a `.ttsmod` with [assetCount] asset entries at
  /// `Backups/[relativePath]`, optionally with its mtime set to [modified].
  String writeBackup(
    String relativePath, {
    int assetCount = 1,
    DateTime? modified,
  }) {
    final file = File(p.join(backupsDir, relativePath))
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        buildZip({
          'Mods/Workshop/mod.json': const [0x7b, 0x7d],
          for (var i = 0; i < assetCount; i++) 'Mods/Images/asset$i.png': [i],
        }),
      );
    if (modified != null) file.setLastModifiedSync(modified);
    return p.normalize(file.path);
  }

  /// Deletes the whole library.
  void delete() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

/// A minimal TTS save file: `SaveName`, optional `EpochTime` and one object
/// per asset carrying the URL under its JSON key.
String modJson({
  required String saveName,
  int? epochTime,
  List<(String, String)> assets = const [],
}) {
  final objects = [
    for (final (key, url) in assets) {'Name': 'Custom', key: url},
  ];
  return const JsonEncoder.withIndent('  ').convert({
    'SaveName': saveName,
    'EpochTime': ?epochTime,
    'ObjectStates': objects,
  });
}

/// A [DirectoriesController] that answers with fixed folders.
final class FixedDirectoriesController extends DirectoriesController {
  FixedDirectoriesController(this._directories);

  final Directories _directories;

  @override
  Future<Directories> build() async => _directories;
}

/// Builds a container for [library] with an in-memory database, a real
/// two-worker pool, an in-memory key-value store and a sink-less log. All of
/// it is torn down with the test.
ProviderContainer makeLibraryContainer(TempLibrary library) {
  final db = AppDatabase(NativeDatabase.memory());
  final pool = WorkerPool(size: 2, debugName: 'library-test');
  final log = AppLog(store: LogStore());
  final container = ProviderContainer.test(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      workerPoolProvider.overrideWithValue(pool),
      appLogProvider.overrideWithValue(log),
      keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      directoriesProvider.overrideWith(
        () => FixedDirectoriesController(library.directories),
      ),
    ],
  );
  addTearDown(() async {
    await pool.dispose();
    await db.close();
    await log.dispose();
  });
  return container;
}

/// The counts of the most recent `Library refresh finished` log line, keyed
/// by the `key=value` names it carries (`scanned`, `parsed`, ...).
Map<String, int> lastRefreshCounts(ProviderContainer container) {
  final entry = container
      .read(appLogProvider)
      .store
      .entries
      .lastWhere((e) => e.message.startsWith(libraryRefreshFinishedPrefix));
  final counts = <String, int>{};
  for (final part in entry.message.split(' ')) {
    final separator = part.indexOf('=');
    if (separator <= 0) continue;
    final value = int.tryParse(part.substring(separator + 1));
    if (value != null) counts[part.substring(0, separator)] = value;
  }
  return counts;
}

/// Number of `Library refresh finished` lines logged so far.
int refreshFinishedLines(ProviderContainer container) => container
    .read(appLogProvider)
    .store
    .entries
    .where((e) => e.message.startsWith(libraryRefreshFinishedPrefix))
    .length;

/// Runs a refresh and returns the resulting state (throws on `AsyncError`).
Future<LibraryState> refreshLibrary(
  ProviderContainer container, {
  bool clearCache = false,
}) async {
  await container
      .read(libraryControllerProvider.notifier)
      .refresh(clearCache: clearCache);
  return container.read(libraryControllerProvider.future);
}
