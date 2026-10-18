// Shared fixtures for the selected-mod panel widget tests: two mods and a
// save with a fixed asset list each (served by an override of
// `modAssetsProvider`, no store reads), a recording library controller, and
// a container whose `ModEditService` runs for real against an in-memory
// database and a `MemoryFileSystem`, so the tests observe its effects
// (files deleted or renamed, JSON rewritten, library patch calls) instead of
// mocking it.

// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'dart:async';
import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/db/daos/mods_dao.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/selected_mod_panel.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

import '../../library/presentation/presentation_test_harness.dart'
    show FixtureDirectoriesController, fixtureDirectories, fixtureMod;

/// Builds an [Asset] for [url]; [exists] gives it the cache path TTS would
/// use under the fixture Mods folder.
Asset fixtureAsset(
  String url,
  AssetType type, {
  bool exists = false,
  bool invalid = false,
}) => Asset(
  url: url,
  type: type,
  fileKey: fileKeyFromUrl(url),
  path: exists
      ? p.join(
          fixtureDirectories.modsDir,
          type.folderName,
          '${fileNameFromUrl(url)}${p.extension(url)}',
        )
      : null,
  invalid: invalid,
);

/// Two mods and one save with fixed assets.
///
/// | mod       | assets                                                   |
/// |-----------|----------------------------------------------------------|
/// | Alpha Mod | img1 (on disk), img2 (missing), model (on disk),         |
/// |           | song (missing, audio), doc.pdf (on disk),                |
/// |           | bundle (missing, invalid)                                |
/// | Beta Mod  | b1 (on disk)                                             |
/// | My Save   | s1 (on disk)                                             |
final class AssetDetailFixture {
  /// Creates the fixture.
  AssetDetailFixture();

  final Asset img1 = fixtureAsset(
    'https://example.com/images/img1.png',
    AssetType.image,
    exists: true,
  );
  final Asset img2 = fixtureAsset(
    'https://example.com/images/img2.png',
    AssetType.image,
  );
  final Asset model = fixtureAsset(
    'https://example.com/models/model.obj',
    AssetType.model,
    exists: true,
  );
  final Asset song = fixtureAsset(
    'https://example.com/audio/song.mp3',
    AssetType.audio,
  );
  final Asset doc = fixtureAsset(
    'https://example.com/docs/doc.pdf',
    AssetType.pdf,
    exists: true,
  );
  final Asset bundle = fixtureAsset(
    'https://example.com/bundles/bundle.unity3d',
    AssetType.assetBundle,
    invalid: true,
  );
  final Asset b1 = fixtureAsset(
    'https://other.com/b1.png',
    AssetType.image,
    exists: true,
  );
  final Asset s1 = fixtureAsset(
    'https://other.com/s1.png',
    AssetType.image,
    exists: true,
  );

  late final Mod alpha = fixtureMod(
    'Alpha Mod',
    id: '100001',
    total: 6,
    present: 3,
    hasAudio: true,
    totalByType: const {
      AssetType.image: 2,
      AssetType.model: 1,
      AssetType.audio: 1,
      AssetType.pdf: 1,
      AssetType.assetBundle: 1,
    },
    presentByType: const {
      AssetType.image: 1,
      AssetType.model: 1,
      AssetType.pdf: 1,
    },
  );

  late final Mod beta = fixtureMod(
    'Beta Mod',
    id: '100002',
    total: 1,
    present: 1,
    totalByType: const {AssetType.image: 1},
    presentByType: const {AssetType.image: 1},
  );

  late final Mod save = fixtureMod(
    'My Save',
    id: 'TS_Save_12',
    type: ModType.save,
    folder: 'Saves',
    total: 1,
    present: 1,
    totalByType: const {AssetType.image: 1},
    presentByType: const {AssetType.image: 1},
  );

  /// Alpha's assets in store order.
  List<Asset> get alphaAssets => [img1, img2, model, song, doc, bundle];

  /// The asset list served for each mod path.
  Map<String, List<Asset>> get assetsByPath => {
    alpha.jsonPath: alphaAssets,
    beta.jsonPath: [b1],
    save.jsonPath: [s1],
  };

  /// The library state the controller serves.
  LibraryState get state => LibraryState(
    mods: [alpha, beta],
    saves: [save],
    lastRefresh: DateTime(2024, 5),
  );
}

/// Library double: serves [initial] without IO and records the patch calls
/// the edit service makes instead of touching the store.
final class RecordingLibraryController extends LibraryController {
  RecordingLibraryController(this.initial);

  /// State returned by `build`.
  final LibraryState initial;

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

/// Everything a panel test needs, torn down with the test.
final class AssetDetailHarness {
  AssetDetailHarness._({
    required this.fixture,
    required this.library,
    required this.store,
    required this.db,
    required this.fs,
    required this.container,
  });

  /// Builds the container. The database holds a row for Alpha (so audio
  /// changes can be read back) and for Beta referencing Alpha's `img1`
  /// file key (so "Shared with" has something to find). [overrides] are
  /// added after the harness's own (fake services, a running operation).
  static Future<AssetDetailHarness> create({
    List<Override> overrides = const [],
  }) async {
    final fixture = AssetDetailFixture();
    final library = RecordingLibraryController(fixture.state);
    final store = InMemoryKeyValueStore();
    final db = AppDatabase(NativeDatabase.memory());
    final fs = MemoryFileSystem(
      style: Platform.isWindows
          ? FileSystemStyle.windows
          : FileSystemStyle.posix,
    );
    final log = AppLog(store: LogStore());

    await db.modsDao.upsertMods([
      _upsertFor(fixture.alpha, fixture.alphaAssets),
      _upsertFor(fixture.beta, [fixture.b1, fixture.img1]),
    ]);

    final container = ProviderContainer.test(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        libraryControllerProvider.overrideWith(() => library),
        directoriesProvider.overrideWith(FixtureDirectoriesController.new),
        appDatabaseProvider.overrideWithValue(db),
        fileSystemProvider.overrideWithValue(fs),
        appLogProvider.overrideWithValue(log),
        modAssetsProvider.overrideWith(
          (ref, path) async => fixture.assetsByPath[path] ?? const <Asset>[],
        ),
        ...overrides,
      ],
    );
    addTearDown(() async {
      await db.close();
      await log.dispose();
    });
    return AssetDetailHarness._(
      fixture: fixture,
      library: library,
      store: store,
      db: db,
      fs: fs,
      container: container,
    );
  }

  static ModUpsert _upsertFor(Mod mod, List<Asset> assets) => ModUpsert(
    ref: mod.ref,
    folder: mod.folder,
    saveName: mod.saveName,
    epochTime: mod.epochTime,
    mtimeMs: mod.modified.millisecondsSinceEpoch,
    sizeBytes: mod.sizeBytes,
    imagePath: mod.imagePath,
    assets: [
      for (final asset in assets)
        (url: asset.url, assetKey: asset.fileKey, type: asset.type),
    ],
  );

  /// The mods and their assets.
  final AssetDetailFixture fixture;

  /// The recording library double.
  final RecordingLibraryController library;

  /// The in-memory key-value store.
  final InMemoryKeyValueStore store;

  /// The in-memory database the edit service writes to.
  final AppDatabase db;

  /// The in-memory file system the edit service writes through.
  final MemoryFileSystem fs;

  /// The container the panel is pumped with.
  final ProviderContainer container;

  /// Selects exactly [mod].
  void select(Mod mod) =>
      container.read(selectionProvider.notifier).select(mod.jsonPath);

  /// Selects every mod in [mods].
  void selectMany(Iterable<Mod> mods) => container
      .read(selectionProvider.notifier)
      .selectMany(mods.map((mod) => mod.jsonPath));

  /// Creates an empty file at [path] in the memory file system.
  void touch(String path) => fs.file(path).createSync(recursive: true);

  /// Writes [contents] to [path] in the memory file system.
  void write(String path, String contents) => fs.file(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  /// Whether a file exists at [path] in the memory file system.
  bool exists(String path) => fs.file(path).existsSync();
}

/// Width of the pumped panel; wide enough for the chips to stay on one or
/// two rows and for the two-line save title.
const double panelWidth = 640;

/// Pumps [SelectedModPanel] inside a themed, localised `MaterialApp` with
/// the providers of [harness] and lets the first frame settle.
Future<void> pumpPanel(WidgetTester tester, AssetDetailHarness harness) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = ThemeSettings.defaults();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        theme: AppTheme.build(settings, Brightness.light),
        darkTheme: AppTheme.build(settings, Brightness.dark),
        themeMode: ThemeMode.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: panelWidth, child: SelectedModPanel()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
