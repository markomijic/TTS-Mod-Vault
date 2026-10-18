// Shared fixtures for the download, URL-check and Workshop operation tests:
// a loopback HTTP server, a MemoryFileSystem holding the TTS folders, an
// in-memory database with the fixture mods' rows, a recording library
// controller and a container wiring the real operations to all of it.

// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/daos/mods_dao.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/data/net/dio_client.dart';
import 'package:tts_mod_vault/data/net/steam_workshop_client.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart';

import '../../data/net/test_http_server.dart';

export '../../data/net/test_http_server.dart';

/// Library double: serves [initial] without IO and records the calls the
/// operations make.
final class RecordingLibrary extends LibraryController {
  RecordingLibrary(this.initial);

  /// State returned by `build`; set before the container first reads the
  /// controller.
  LibraryState initial;

  /// Paths passed to `resummarizeMod`.
  final List<String> resummarizeCalls = [];

  /// Paths passed to `refreshMod`.
  final List<String> refreshModCalls = [];

  /// File-key sets passed to `applyAssetFileChange`.
  final List<Set<String>> assetFileChangeCalls = [];

  @override
  FutureOr<LibraryState> build() => initial;

  @override
  Future<void> refresh({bool clearCache = false}) async {}

  @override
  Future<void> resummarizeMod(String jsonPath) async {
    resummarizeCalls.add(jsonPath);
  }

  @override
  Future<void> refreshMod(String jsonPath, {ModType? type}) async {
    refreshModCalls.add(jsonPath);
  }

  @override
  Future<void> applyAssetFileChange(Set<String> fileKeys) async {
    assetFileChangeCalls.add(fileKeys);
  }
}

/// A [DirectoriesController] that answers with fixed folders.
final class _FixedDirectories extends DirectoriesController {
  _FixedDirectories(this._directories);

  final Directories _directories;

  @override
  Future<Directories> build() async => _directories;
}

/// Everything an operation test needs, torn down with the test.
final class DownloadsHarness {
  DownloadsHarness._({
    required this.server,
    required this.fs,
    required this.directories,
    required this.db,
    required this.log,
    required this.library,
    required this.dio,
    required this.container,
  });

  /// Starts the server and builds the container. Call [indexMods] next to
  /// put fixture mods (whose asset URLs point at [server]) into the
  /// database and the library state. [steamDetailsPath] is the server
  /// route the Steam client posts to (`/details-garbage` for a broken API).
  static Future<DownloadsHarness> create({
    String steamDetailsPath = '/details',
  }) async {
    final server = await TestHttpServer.start();
    final fs = MemoryFileSystem(
      style: Platform.isWindows
          ? FileSystemStyle.windows
          : FileSystemStyle.posix,
    );
    final root = p.join(fs.currentDirectory.path, 'TTS');
    final directories = Directories(
      modsDir: p.join(root, 'Mods'),
      savesDir: p.join(root, 'Saves'),
    );
    fs.directory(directories.workshopDir).createSync(recursive: true);
    for (final type in AssetType.values) {
      fs.directory(directories.assetDir(type)).createSync(recursive: true);
    }
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    final log = AppLog(store: LogStore());
    final library = RecordingLibrary(
      LibraryState(lastRefresh: DateTime(2024, 5)),
    );
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    final container = ProviderContainer.test(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        libraryControllerProvider.overrideWith(() => library),
        directoriesProvider.overrideWith(() => _FixedDirectories(directories)),
        appDatabaseProvider.overrideWithValue(db),
        fileSystemProvider.overrideWithValue(fs),
        appLogProvider.overrideWithValue(log),
        dioProvider.overrideWithValue(dio),
        steamWorkshopClientProvider.overrideWithValue(
          SteamWorkshopClient(dio: dio, apiUrl: server.url(steamDetailsPath)),
        ),
      ],
    );
    addTearDown(() async {
      dio.close(force: true);
      await server.close();
      await db.close();
      await log.dispose();
    });
    return DownloadsHarness._(
      server: server,
      fs: fs,
      directories: directories,
      db: db,
      log: log,
      library: library,
      dio: dio,
      container: container,
    );
  }

  /// The loopback HTTP server.
  final TestHttpServer server;

  /// The in-memory file system holding the TTS folders.
  final MemoryFileSystem fs;

  /// The TTS folders inside [fs].
  final Directories directories;

  /// The in-memory database.
  final AppDatabase db;

  /// The sink-less log.
  final AppLog log;

  /// The recording library double.
  final RecordingLibrary library;

  /// The HTTP client every network class uses.
  final Dio dio;

  /// The container the operations run in.
  final ProviderContainer container;

  /// Indexes [mods] in the database with the assets [assetsOf] gives for
  /// each JSON path (URL and type) and serves them as the library state.
  Future<void> indexMods(
    List<Mod> mods,
    Map<String, List<(String url, AssetType type)>> assetsOf,
  ) async {
    await db.modsDao.upsertMods([
      for (final mod in mods)
        ModUpsert(
          ref: mod.ref,
          folder: mod.folder,
          saveName: mod.saveName,
          epochTime: mod.epochTime,
          mtimeMs: mod.modified.millisecondsSinceEpoch,
          sizeBytes: mod.sizeBytes,
          imagePath: mod.imagePath,
          assets: [
            for (final (url, type)
                in assetsOf[mod.jsonPath] ?? const <(String, AssetType)>[])
              (url: url, assetKey: type.jsonKeys.first, type: type),
          ],
        ),
    ]);
    library.initial = LibraryState(mods: mods, lastRefresh: DateTime(2024, 5));
  }

  /// The mod's assets as the store currently joins them.
  Future<List<Asset>> assetsInStore(Mod mod) =>
      db.libraryQueries.assetsForMod(mod.jsonPath);

  /// Builds a Workshop mod of the fixture library with [id]; its JSON path
  /// is `Mods/Workshop/<id>.json` (not written to the file system).
  Mod workshopMod(
    String id, {
    String? saveName,
    int? epochTime,
    AudioVisibility audio = AudioVisibility.useGlobalSetting,
  }) => Mod(
    ref: ModRef.fromPath(
      ModType.mod,
      p.join(directories.workshopDir, '$id.json'),
    ),
    saveName: saveName ?? 'Mod $id',
    folder: 'Workshop',
    epochTime: epochTime,
    modified: DateTime(2024, 3),
    sizeBytes: 1024,
    imagePath: null,
    audio: audio,
    summary: const AssetSummary(
      total: 0,
      present: 0,
      hasAudio: false,
      totalByType: {},
      presentByType: {},
    ),
  );

  /// The cache path TTS would give [url] of [type] with [extension].
  String cachePath(AssetType type, String url, {String extension = '.png'}) =>
      p.join(directories.assetDir(type), '${fileNameFromUrl(url)}$extension');

  /// File names in the cache folder of [type].
  List<String> cachedFiles(AssetType type) => [
    for (final entity in fs.directory(directories.assetDir(type)).listSync())
      p.basename(entity.path),
  ]..sort();

  /// Every progress snapshot the runner publishes from now on.
  List<OperationProgress> recordProgress() {
    final snapshots = <OperationProgress>[];
    container.listen(operationRunnerProvider, (_, next) {
      final progress = next.progress;
      if (progress != null) snapshots.add(progress);
    });
    return snapshots;
  }

  /// The runner's current state.
  OperationState get runnerState => container.read(operationRunnerProvider);

  /// Log messages in order.
  List<String> get logMessages =>
      log.store.entries.map((e) => e.message).toList();
}
