// Integration tests of the library refresh pipeline against a temporary
// library on disk: real worker isolates, real zip reading, in-memory SQLite.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/application/refresh_progress.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

import 'library_test_harness.dart';

const _imageA = 'https://example.com/a.png';
const _imageB = 'https://example.com/b.png';
const _model = 'https://example.com/m.obj';
const _audio = 'https://example.com/s.mp3';

/// The reference library every test starts from:
///
/// | file                      | name   | epoch | assets                          | backup                              |
/// | Workshop/111.json (+png)  | Alpha  | 2023  | image a (present), model, audio | Alpha (111) x2, newest has 1 asset  |
/// | Workshop/Sub/222.json     | Beta   | 2023  | image b (missing)               | Beta (222), 2 assets -> mismatch    |
/// | Workshop/333.json         | Gamma  | 2023  | image a (present)               | Gamma (333), dated 2020 -> out of date |
/// | Workshop/444.json         | Delta  | none  | none                            | none                                |
/// | Workshop/Old/555.json     | Old    | none  | none                            | (hidden by the ignored-folder test) |
/// | Saves/TS_Save_1.json      | My Save| 2023  | none                            | none                                |
/// | Saves/Saved Objects/Obj   | Obj    | none  | none                            | (shown by the saved-objects test)   |
/// plus `Backups/stray.ttsmod`, which matches nothing.
final class _Fixture {
  _Fixture(this.library) {
    alpha = library.writeJson(
      p.join('Mods', 'Workshop', '111.json'),
      saveName: 'Alpha',
      epochTime: epoch2023,
      assets: [
        ('ImageURL', _imageA),
        ('MeshURL', _model),
        ('CurrentAudioURL', _audio),
      ],
    );
    alphaImage = library.writeSiblingImage(alpha);
    beta = library.writeJson(
      p.join('Mods', 'Workshop', 'Sub', '222.json'),
      saveName: 'Beta',
      epochTime: epoch2023,
      assets: [('ImageURL', _imageB)],
    );
    gamma = library.writeJson(
      p.join('Mods', 'Workshop', '333.json'),
      saveName: 'Gamma',
      epochTime: epoch2023,
      assets: [('FaceURL', _imageA)],
    );
    delta = library.writeJson(
      p.join('Mods', 'Workshop', '444.json'),
      saveName: 'Delta',
    );
    old = library.writeJson(
      p.join('Mods', 'Workshop', 'Old', '555.json'),
      saveName: 'Old',
    );
    save = library.writeJson(
      p.join('Saves', 'TS_Save_1.json'),
      saveName: 'My Save',
      epochTime: epoch2023,
    );
    savedObject = library.writeJson(
      p.join('Saves', 'Saved Objects', 'Obj.json'),
      saveName: '',
    );

    library.writeAsset(AssetType.image, _imageA);
    library.writeAsset(AssetType.audio, _audio, extension: '.mp3');

    alphaBackup = library.writeBackup('Alpha (111).ttsmod');
    library.writeBackup(
      p.join('Older', 'Alpha (111).ttsmod'),
      assetCount: 5,
      modified: DateTime.fromMillisecondsSinceEpoch(epoch2020 * 1000),
    );
    betaBackup = library.writeBackup('Beta (222).ttsmod', assetCount: 2);
    gammaBackup = library.writeBackup(
      'Gamma (333).ttsmod',
      modified: DateTime.fromMillisecondsSinceEpoch(epoch2020 * 1000),
    );
    library.writeBackup('stray.ttsmod');
  }

  final TempLibrary library;
  late final String alpha;
  late final String alphaImage;
  late final String beta;
  late final String gamma;
  late final String delta;
  late final String old;
  late final String save;
  late final String savedObject;
  late final String alphaBackup;
  late final String betaBackup;
  late final String gammaBackup;

  /// Files the default options index (saved objects off, `Old` not ignored).
  int get defaultFileCount => 6;
}

void main() {
  late TempLibrary library;
  late _Fixture fixture;
  late ProviderContainer container;

  setUp(() {
    library = TempLibrary.create();
    fixture = _Fixture(library);
    container = makeLibraryContainer(library);
  });

  tearDown(() => library.delete());

  Mod modNamed(LibraryState state, String name) =>
      state.all.singleWhere((m) => m.saveName == name);

  test('build does no IO and starts empty', () async {
    final state = await container.read(libraryControllerProvider.future);
    expect(state.isEmpty, isTrue);
    expect(state.lastRefresh, isNull);
    expect(refreshFinishedLines(container), 0);
  });

  test('first refresh indexes mods, saves, counts and backups', () async {
    final stopwatch = Stopwatch()..start();
    final state = await refreshLibrary(container);
    stopwatch.stop();
    // Reported in the task summary; generous bound so slow CI does not fail.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));

    expect(state.mods.map((m) => m.saveName), [
      'Alpha',
      'Beta',
      'Delta',
      'Gamma',
      'Old',
    ]);
    expect(state.saves.map((m) => m.saveName), ['My Save']);
    expect(state.savedObjects, isEmpty);
    expect(state.warnings, isEmpty);
    expect(state.lastRefresh, isNotNull);

    final alpha = modNamed(state, 'Alpha');
    expect(alpha.ref.id, '111');
    expect(alpha.ref.type, ModType.mod);
    expect(alpha.jsonPath, fixture.alpha);
    expect(alpha.folder, 'Workshop');
    expect(alpha.imagePath, fixture.alphaImage);
    expect(alpha.epochTime, epoch2023);
    expect(alpha.sizeBytes, File(fixture.alpha).lengthSync());
    // Audio is hidden by default: 2 counted (image present, model missing).
    expect(alpha.summary.total, 2);
    expect(alpha.summary.present, 1);
    expect(alpha.summary.hasAudio, isTrue);
    expect(alpha.summary.totalByType, {AssetType.image: 1, AssetType.model: 1});
    expect(alpha.summary.presentByType, {
      AssetType.image: 1,
      AssetType.model: 0,
    });

    final beta = modNamed(state, 'Beta');
    expect(beta.folder, 'Sub');
    expect(beta.imagePath, isNull);
    expect(beta.summary.total, 1);
    expect(beta.summary.present, 0);
    expect(beta.summary.hasAudio, isFalse);

    final delta = modNamed(state, 'Delta');
    expect(delta.summary, AssetSummary.empty);
    expect(delta.epochTime, isNull);

    final save = modNamed(state, 'My Save');
    expect(save.ref.type, ModType.save);
    expect(save.folder, 'Saves');

    final counts = lastRefreshCounts(container);
    expect(counts['mods'], 5);
    expect(counts['saves'], 1);
    expect(counts['savedObjects'], 0);
    expect(counts['backups'], 5);
    expect(counts['scanned'], fixture.defaultFileCount);
    expect(counts['parsed'], fixture.defaultFileCount);
    expect(counts['removed'], 0);
    expect(counts['backupsCounted'], 5);
    expect(counts['warnings'], 0);
    expect(counts['durationMs'], isNotNull);
    expect(container.read(refreshProgressProvider), isNull);
  });

  test('backups are matched by name, newest first, with a status', () async {
    final state = await refreshLibrary(container);

    final alpha = modNamed(state, 'Alpha');
    expect(alpha.backup?.path, fixture.alphaBackup);
    expect(alpha.backup?.folder, 'Backups');
    expect(alpha.backup?.assetCount, 1);
    expect(alpha.backup?.matchingModPath, fixture.alpha);
    // Newer than the save time and 1 asset == 1 present.
    expect(alpha.backupStatus, BackupStatus.upToDate);

    final beta = modNamed(state, 'Beta');
    expect(beta.backup?.path, fixture.betaBackup);
    expect(beta.backupStatus, BackupStatus.assetCountMismatch);

    final gamma = modNamed(state, 'Gamma');
    expect(gamma.backup?.path, fixture.gammaBackup);
    expect(gamma.backupStatus, BackupStatus.outOfDate);

    final delta = modNamed(state, 'Delta');
    expect(delta.backup, isNull);
    expect(delta.backupStatus, BackupStatus.none);

    expect(state.backups, hasLength(5));
    final older = state.backups.singleWhere((b) => b.folder == 'Older');
    expect(older.fileName, 'Alpha (111).ttsmod');
    expect(older.assetCount, 5);
    expect(older.matchingModPath, isNull, reason: 'the newer one matched');
    final stray = state.backups.singleWhere(
      (b) => b.fileName == 'stray.ttsmod',
    );
    expect(stray.hasMatchingMod, isFalse);
    expect(
      state.backups.where((b) => b.hasMatchingMod).map((b) => b.fileName),
      unorderedEquals([
        'Alpha (111).ttsmod',
        'Beta (222).ttsmod',
        'Gamma (333).ttsmod',
      ]),
    );
  });

  test('a second refresh parses nothing and reads no zip', () async {
    final first = await refreshLibrary(container);
    final second = await refreshLibrary(container);

    final counts = lastRefreshCounts(container);
    expect(counts['scanned'], fixture.defaultFileCount);
    expect(counts['parsed'], 0);
    expect(counts['removed'], 0);
    expect(counts['backupsCounted'], 0);
    expect(refreshFinishedLines(container), 2);
    expect(
      second.all.map((m) => (m.jsonPath, m.saveName, m.summary)),
      first.all.map((m) => (m.jsonPath, m.saveName, m.summary)),
    );
    expect(
      second.all.map((m) => m.backupStatus),
      first.all.map((m) => m.backupStatus),
    );
  });

  test('a changed file is the only one re-parsed', () async {
    await refreshLibrary(container);

    // Different content and size; the mtime moves on its own.
    library.writeJson(
      p.join('Mods', 'Workshop', 'Sub', '222.json'),
      saveName: 'Beta renamed',
      epochTime: epoch2023,
      assets: [('ImageURL', _imageB), ('ImageURL', _imageA)],
    );
    final state = await refreshLibrary(container);

    expect(lastRefreshCounts(container)['parsed'], 1);
    final beta = state.modByPath(fixture.beta)!;
    expect(beta.saveName, 'Beta renamed');
    expect(beta.summary.total, 2);
    expect(beta.summary.present, 1);
    // The backup name no longer matches the new save name.
    expect(beta.backup, isNull);
    expect(beta.backupStatus, BackupStatus.none);
  });

  test('a deleted file is removed from the state and the store', () async {
    await refreshLibrary(container);
    File(fixture.delta).deleteSync();

    final state = await refreshLibrary(container);

    expect(state.modByPath(fixture.delta), isNull);
    expect(state.mods.map((m) => m.saveName), isNot(contains('Delta')));
    final counts = lastRefreshCounts(container);
    expect(counts['removed'], 1);
    expect(counts['parsed'], 0);
    final db = container.read(appDatabaseProvider);
    expect(
      (await db.modsDao.fingerprints()).keys,
      isNot(contains(fixture.delta)),
    );
  });

  test('a deleted backup drops out of the index', () async {
    await refreshLibrary(container);
    File(fixture.gammaBackup).deleteSync();

    final state = await refreshLibrary(container);

    expect(
      state.backups.map((b) => b.path),
      isNot(contains(fixture.gammaBackup)),
    );
    expect(modNamed(state, 'Gamma').backupStatus, BackupStatus.none);
    final db = container.read(appDatabaseProvider);
    expect(
      (await db.backupsDao.fingerprints()).keys,
      isNot(contains(fixture.gammaBackup)),
    );
  });

  test('clearCache re-parses every file and re-counts every backup', () async {
    await refreshLibrary(container);
    final state = await refreshLibrary(container, clearCache: true);

    final counts = lastRefreshCounts(container);
    expect(counts['parsed'], fixture.defaultFileCount);
    expect(counts['backupsCounted'], 5);
    expect(state.mods, hasLength(5));
    expect(modNamed(state, 'Alpha').backupStatus, BackupStatus.upToDate);
  });

  test('a missing Saves folder is a warning, not an error', () async {
    // Let the controller's build finish before replacing its value.
    await container.read(directoriesProvider.future);
    await container
        .read(directoriesProvider.notifier)
        .set(
          library.directories.copyWith(
            savesDir: p.join(library.root.path, 'NoSuchSaves'),
          ),
        );

    final state = await refreshLibrary(container);

    expect(state.saves, isEmpty);
    expect(state.mods, hasLength(5));
    expect(state.warnings, hasLength(1));
    expect(state.warnings.single, contains('Directory not found'));
    expect(state.warnings.single, contains('NoSuchSaves'));
    final log = container.read(appLogProvider).store.entries;
    expect(
      log.where((e) => e.level == LogLevel.warning).map((e) => e.message),
      contains(state.warnings.single),
    );
    expect(lastRefreshCounts(container)['warnings'], 1);
  });

  test('an unreadable JSON is skipped with a warning', () async {
    final bad = File(p.join(library.workshopDir, 'bad.json'))
      ..writeAsBytesSync(const [0xFF, 0xFE, 0x80, 0x22]);

    final state = await refreshLibrary(container);

    expect(state.modByPath(p.normalize(bad.path)), isNull);
    expect(state.mods, hasLength(5));
    expect(state.warnings, hasLength(1));
    expect(state.warnings.single, startsWith('Could not read '));
    expect(state.warnings.single, contains('bad.json'));
    final counts = lastRefreshCounts(container);
    expect(counts['scanned'], fixture.defaultFileCount + 1);
    expect(counts['parsed'], fixture.defaultFileCount);
    final log = container.read(appLogProvider).store.entries;
    expect(
      log.any(
        (e) =>
            e.level == LogLevel.warning &&
            e.message == 'Could not read mod file' &&
            e.modPath == p.normalize(bad.path),
      ),
      isTrue,
    );
  });

  test('saved objects and ignored subfolders follow the options', () async {
    await container
        .read(libraryOptionsProvider.notifier)
        .set(
          const LibraryOptions(
            includeSavedObjects: true,
            ignoredSubfolders: ['Old'],
          ),
        );

    final state = await refreshLibrary(container);

    expect(state.mods.map((m) => m.saveName), [
      'Alpha',
      'Beta',
      'Delta',
      'Gamma',
    ]);
    expect(state.savedObjects.map((m) => m.saveName), ['Obj']);
    final obj = state.savedObjects.single;
    expect(obj.ref.type, ModType.savedObject);
    expect(obj.jsonPath, fixture.savedObject);
    expect(obj.folder, 'Saved Objects');
    expect(lastRefreshCounts(container)['scanned'], 6);
  });

  test('audio counts follow ignoreAudioGlobally', () async {
    await container
        .read(libraryOptionsProvider.notifier)
        .set(const LibraryOptions(ignoreAudioGlobally: false));

    final state = await refreshLibrary(container);

    final alpha = modNamed(state, 'Alpha');
    expect(alpha.summary.total, 3);
    expect(alpha.summary.present, 2);
    expect(alpha.summary.totalOf(AssetType.audio), 1);
    // 1 asset in the backup vs 2 present: no longer up to date.
    expect(alpha.backupStatus, BackupStatus.assetCountMismatch);
  });

  test('without a backups folder no backups are indexed', () async {
    await container.read(directoriesProvider.future);
    await container
        .read(directoriesProvider.notifier)
        .set(library.directories.copyWith(backupsDir: ''));

    final state = await refreshLibrary(container);

    expect(state.backups, isEmpty);
    expect(state.warnings, isEmpty);
    expect(modNamed(state, 'Alpha').backupStatus, BackupStatus.none);
  });

  test('the previous state stays visible while a refresh runs', () async {
    final first = await refreshLibrary(container);

    final running = container
        .read(libraryControllerProvider.notifier)
        .refresh();
    final during = container.read(libraryControllerProvider);
    expect(during.isLoading, isTrue);
    expect(during.value, isNotNull);
    expect(during.value!.mods, hasLength(first.mods.length));
    await running;

    expect(container.read(libraryControllerProvider).isLoading, isFalse);
  });

  test('concurrent refresh calls share one run', () async {
    final notifier = container.read(libraryControllerProvider.notifier);
    final a = notifier.refresh();
    final b = notifier.refresh(clearCache: true);
    expect(identical(a, b), isTrue);
    await Future.wait([a, b]);

    expect(refreshFinishedLines(container), 1);
    expect(container.read(libraryControllerProvider).value!.mods, hasLength(5));
  });

  test('progress walks through every phase and ends idle', () async {
    // The derived `refreshProgressProvider` is what the UI watches; its
    // rebuilds are scheduled, so a phase that finishes within one event-loop
    // turn (summarizing on an in-memory database) is coalesced away there.
    // The controller provider notifies synchronously and shows every step.
    final seen = <RefreshProgress?>[];
    final subscription = container.listen(
      refreshProgressControllerProvider,
      (_, next) => seen.add(next),
    );
    addTearDown(subscription.close);
    expect(container.read(refreshProgressProvider), isNull);

    await refreshLibrary(container);

    final phases = seen.nonNulls.map((s) => s.phase).toList();
    expect(phases.toSet(), LibraryRefreshPhase.values.toSet());
    // Phases appear in pipeline order.
    expect(
      phases.map((phase) => phase.index).fold<int>(-1, (last, index) {
        expect(index, greaterThanOrEqualTo(last));
        return index;
      }),
      LibraryRefreshPhase.summarizing.index,
    );
    expect(seen.last, isNull);
    expect(container.read(refreshProgressProvider), isNull);
    final parsing = seen.nonNulls.where(
      (s) => s.phase == LibraryRefreshPhase.parsing,
    );
    expect(parsing.first.total, fixture.defaultFileCount);
    expect(parsing.last.done, fixture.defaultFileCount);
    expect(parsing.last.fraction, 1);
  });

  test('refreshMod re-reads one file without a full refresh', () async {
    await refreshLibrary(container);
    library.writeJson(
      p.join('Mods', 'Workshop', '444.json'),
      saveName: 'Delta',
      epochTime: epoch2023,
      assets: [('ImageURL', _imageA), ('PDFUrl', 'https://example.com/r.pdf')],
    );

    await container
        .read(libraryControllerProvider.notifier)
        .refreshMod(fixture.delta);

    final state = container.read(libraryControllerProvider).value!;
    final delta = state.modByPath(fixture.delta)!;
    expect(delta.epochTime, epoch2023);
    expect(delta.summary.total, 2);
    expect(delta.summary.present, 1);
    expect(delta.summary.totalOf(AssetType.pdf), 1);
    expect(refreshFinishedLines(container), 1, reason: 'no full refresh ran');
    // Everything else is untouched.
    expect(state.mods, hasLength(5));
    expect(modNamed(state, 'Alpha').backupStatus, BackupStatus.upToDate);
    // The store agrees, so the next refresh has nothing to parse.
    await refreshLibrary(container);
    expect(lastRefreshCounts(container)['parsed'], 0);
  });

  test('refreshMod ignores unknown paths', () async {
    await refreshLibrary(container);
    await container
        .read(libraryControllerProvider.notifier)
        .refreshMod(p.join(library.workshopDir, 'nope.json'));
    expect(container.read(libraryControllerProvider).value!.mods, hasLength(5));
  });

  test('applyAssetFileChange re-summarises the referencing mods', () async {
    await refreshLibrary(container);
    final path = library.writeAsset(AssetType.image, _imageB);
    final key = fileKeyFromUrl(_imageB);
    await container
        .read(appDatabaseProvider)
        .existingFilesDao
        .upsert(AssetType.image, key, path);

    await container
        .read(libraryControllerProvider.notifier)
        .applyAssetFileChange({key});

    final state = container.read(libraryControllerProvider).value!;
    final beta = state.modByPath(fixture.beta)!;
    expect(beta.summary.present, 1);
    expect(beta.summary.isComplete, isTrue);
    // Beta's backup holds 2 assets, 1 present: still a mismatch.
    expect(beta.backupStatus, BackupStatus.assetCountMismatch);
    expect(beta.folder, 'Sub');
    expect(refreshFinishedLines(container), 1);
  });

  test(
    'a failing refresh ends as AsyncError with the previous value',
    () async {
      final first = await refreshLibrary(container);
      await container.read(workerPoolProvider).dispose();

      await container.read(libraryControllerProvider.notifier).refresh();

      final state = container.read(libraryControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.value?.mods, hasLength(first.mods.length));
      expect(container.read(refreshProgressProvider), isNull);
      final errors = container
          .read(appLogProvider)
          .store
          .entries
          .where((e) => e.level == LogLevel.error);
      expect(errors.single.message, 'Library refresh failed');
      await expectLater(
        container.read(libraryControllerProvider.future),
        throwsA(isA<StateError>()),
      );
    },
  );
}
