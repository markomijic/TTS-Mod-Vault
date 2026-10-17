// Shared fixtures for the library page widget tests: a fixed library of six
// mods and one save (no IO beyond one tiny PNG for the "image present"
// case), a spy library controller and a pump helper that renders the page
// inside a themed, localised MaterialApp at desktop size.

// Test doubles expose counters and recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/presentation/library_page.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// A 1x1 transparent PNG.
final List<int> onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// Root of the fake TTS library; nothing under it exists except
/// [FixtureLibrary.imagePath].
final String fixtureRoot = p.join(
  Directory.systemTemp.path,
  'ttsmv_presentation_fixture',
);

/// The folders the fake library pretends to live in.
final Directories fixtureDirectories = Directories(
  modsDir: p.join(fixtureRoot, 'Mods'),
  savesDir: p.join(fixtureRoot, 'Saves'),
  backupsDir: p.join(fixtureRoot, 'Backups'),
);

/// Builds a mod of [type] with the given counts and backup.
Mod fixtureMod(
  String name, {
  required String id,
  ModType type = ModType.mod,
  String folder = 'Workshop',
  int? epoch,
  DateTime? modified,
  int total = 0,
  int present = 0,
  bool hasAudio = false,
  Map<AssetType, int> totalByType = const {},
  Map<AssetType, int> presentByType = const {},
  String? imagePath,
  BackupStatus backupStatus = BackupStatus.none,
  int backupAssetCount = 0,
}) {
  final parent = switch (type) {
    ModType.mod => fixtureDirectories.workshopDir,
    ModType.save => fixtureDirectories.savesDir,
    ModType.savedObject => fixtureDirectories.savedObjectsDir,
  };
  final jsonPath = p.join(
    parent,
    folder == 'Workshop' ? '' : folder,
    '$id.json',
  );
  final hasBackup = backupStatus != BackupStatus.none;
  return Mod(
    ref: ModRef.fromPath(type, jsonPath),
    saveName: name,
    folder: folder,
    epochTime: epoch,
    modified: modified ?? DateTime(2024, 1, 15, 10, 30),
    sizeBytes: 1024,
    imagePath: imagePath,
    audio: AudioVisibility.useGlobalSetting,
    summary: AssetSummary(
      total: total,
      present: present,
      hasAudio: hasAudio,
      totalByType: totalByType,
      presentByType: presentByType,
    ),
    backupStatus: backupStatus,
    backup: hasBackup
        ? Backup(
            path: p.join(fixtureDirectories.backupsDir, '$name.ttsmod'),
            fileName: '$name.ttsmod',
            folder: 'Backups',
            modified: DateTime(2024, 2, 1, 12),
            sizeBytes: 4096,
            assetCount: backupAssetCount,
            matchingModPath: p.normalize(jsonPath),
          )
        : null,
  );
}

/// The fixed library every test renders.
///
/// Mods (type `mod`), default A-Z order: Alpha, Beta, Delta, Epsilon, Gamma.
///
/// | name    | folder     | image            | backup            | missing | audio |
/// |---------|------------|------------------|-------------------|---------|-------|
/// | Alpha   | Workshop   | real PNG         | upToDate          | 0 of 4  | no    |
/// | Beta    | Workshop   | none             | outOfDate         | 2 of 5  | yes   |
/// | Gamma   | Favourites | none             | assetCountMismatch| 1 of 3  | no    |
/// | Delta   | Favourites | none             | none              | 0 of 0  | no    |
/// | Epsilon | Workshop   | missing file     | none              | 3 of 3  | no    |
///
/// Plus one save, "My Save", in `Saves`.
final class FixtureLibrary {
  FixtureLibrary._(this.imagePath);

  /// Writes the PNG and builds the mods.
  factory FixtureLibrary.create() {
    Directory(fixtureRoot).createSync(recursive: true);
    final imagePath = p.join(fixtureRoot, 'alpha.png');
    File(imagePath).writeAsBytesSync(onePixelPng);
    return FixtureLibrary._(imagePath);
  }

  /// Path of the real PNG used by Alpha.
  final String imagePath;

  late final Mod alpha = fixtureMod(
    'Alpha Mod',
    id: '100001',
    epoch: 1_700_000_000,
    modified: DateTime(2024, 3),
    total: 4,
    present: 4,
    totalByType: const {AssetType.image: 3, AssetType.model: 1},
    presentByType: const {AssetType.image: 3, AssetType.model: 1},
    imagePath: imagePath,
    backupStatus: BackupStatus.upToDate,
    backupAssetCount: 4,
  );

  late final Mod beta = fixtureMod(
    'Beta Mod',
    id: '100002',
    epoch: 1_600_000_000,
    modified: DateTime(2024, 2),
    total: 5,
    present: 3,
    hasAudio: true,
    totalByType: const {AssetType.image: 4, AssetType.audio: 1},
    presentByType: const {AssetType.image: 3},
    backupStatus: BackupStatus.outOfDate,
    backupAssetCount: 3,
  );

  late final Mod gamma = fixtureMod(
    'Gamma Mod',
    id: '100003',
    folder: 'Favourites',
    epoch: 1_650_000_000,
    modified: DateTime(2024),
    total: 3,
    present: 2,
    totalByType: const {AssetType.pdf: 3},
    presentByType: const {AssetType.pdf: 2},
    backupStatus: BackupStatus.assetCountMismatch,
    backupAssetCount: 9,
  );

  late final Mod delta = fixtureMod(
    'Delta Mod',
    id: '100004',
    folder: 'Favourites',
    modified: DateTime(2023, 12),
  );

  late final Mod epsilon = fixtureMod(
    'Epsilon Mod',
    id: '100005',
    epoch: 1_750_000_000,
    modified: DateTime(2024, 4),
    total: 3,
    totalByType: const {AssetType.assetBundle: 3},
    imagePath: p.join(fixtureRoot, 'does-not-exist.png'),
  );

  late final Mod save = fixtureMod(
    'My Save',
    id: 'TS_Save_12',
    type: ModType.save,
    folder: 'Saves',
    total: 2,
    present: 2,
  );

  /// Every fixture mod of type `mod`, in no particular order.
  List<Mod> get mods => [gamma, alpha, epsilon, beta, delta];

  /// The library state the fake controller serves.
  LibraryState get state =>
      LibraryState(mods: mods, saves: [save], lastRefresh: DateTime(2024, 5));

  /// Deletes the PNG.
  void delete() {
    final dir = Directory(fixtureRoot);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Library controller double: serves [initial] and records `refresh` calls
/// without doing any IO.
final class SpyLibraryController extends LibraryController {
  SpyLibraryController(this.initial);

  /// State returned by `build`.
  final LibraryState initial;

  /// `clearCache` argument of every `refresh` call.
  final List<bool> refreshCalls = [];

  @override
  FutureOr<LibraryState> build() => initial;

  @override
  Future<void> refresh({bool clearCache = false}) async {
    refreshCalls.add(clearCache);
  }
}

/// A [DirectoriesController] that answers with [directories], by default
/// [fixtureDirectories].
final class FixtureDirectoriesController extends DirectoriesController {
  FixtureDirectoriesController([Directories? directories])
    : directories = directories ?? fixtureDirectories;

  /// The folders served by `build`.
  final Directories directories;

  @override
  Future<Directories> build() async => directories;
}

/// The overrides every library page test needs. [directories] replaces
/// [fixtureDirectories] (for example to drop the backups folder).
List<Override> libraryPageOverrides({
  required LibraryController Function() library,
  InMemoryKeyValueStore? store,
  Directories? directories,
}) => [
  keyValueStoreProvider.overrideWithValue(store ?? InMemoryKeyValueStore()),
  libraryControllerProvider.overrideWith(library),
  directoriesProvider.overrideWith(
    () => FixtureDirectoriesController(directories),
  ),
  // The selected-mod panel reads the store for the asset list; serve none.
  modAssetsProvider.overrideWith((ref, path) async => const <Asset>[]),
];

/// Pumps [LibraryPage] inside a themed, localised `MaterialApp` with the
/// providers of [container], at a window wide enough for the two-column
/// layout, and lets the first frame settle.
Future<void> pumpLibraryPage(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = ThemeSettings.defaults();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.build(settings, Brightness.light),
        darkTheme: AppTheme.build(settings, Brightness.dark),
        themeMode: ThemeMode.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: LibraryPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
