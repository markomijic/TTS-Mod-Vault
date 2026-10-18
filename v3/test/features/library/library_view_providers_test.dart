// Filtering, sorting and selection over a fixed LibraryState; no IO.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';

final class _FixedLibraryController extends LibraryController {
  _FixedLibraryController(this._state);

  final LibraryState _state;

  @override
  FutureOr<LibraryState> build() => _state;
}

Mod mod(
  String name, {
  ModType type = ModType.mod,
  String folder = 'Workshop',
  int? epoch,
  DateTime? modified,
  int total = 0,
  int present = 0,
  bool hasAudio = false,
  Map<AssetType, int> byType = const {},
  BackupStatus backupStatus = BackupStatus.none,
}) => Mod(
  ref: ModRef.fromPath(type, p.join('lib', folder, '$name.json')),
  saveName: name,
  folder: folder,
  epochTime: epoch,
  modified: modified ?? DateTime(2024),
  sizeBytes: 1,
  imagePath: null,
  audio: AudioVisibility.useGlobalSetting,
  summary: AssetSummary(
    total: total,
    present: present,
    hasAudio: hasAudio,
    totalByType: byType,
    presentByType: const {},
  ),
  backupStatus: backupStatus,
);

void main() {
  // Mods: deliberately not in name order to prove sorting.
  final zeta = mod(
    'zeta',
    epoch: 1000,
    modified: DateTime(2024, 3),
    total: 3,
    present: 1,
    byType: {AssetType.image: 2, AssetType.model: 1},
    backupStatus: BackupStatus.upToDate,
  );
  final alpha = mod(
    'Alpha',
    folder: 'Sub',
    epoch: 3000,
    modified: DateTime(2024),
    total: 2,
    present: 2,
    hasAudio: true,
    byType: {AssetType.pdf: 2},
    backupStatus: BackupStatus.outOfDate,
  );
  final mid = mod(
    'mid',
    // No epoch: `newest` falls back to the file mtime (2024-02 = 1.7e12 ms,
    // far later than epoch 3000 s).
    modified: DateTime(2024, 2),
    total: 4,
    byType: {AssetType.assetBundle: 4},
  );
  final save = mod('A save', type: ModType.save, folder: 'Saves');
  final savedObject = mod(
    'Obj',
    type: ModType.savedObject,
    folder: 'Saved Objects',
  );

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer.test(
      overrides: [
        libraryControllerProvider.overrideWith(
          () => _FixedLibraryController(
            LibraryState(
              mods: [zeta, alpha, mid],
              saves: [save],
              savedObjects: [savedObject],
            ),
          ),
        ),
      ],
    );
  });

  List<String> names() =>
      container.read(filteredModsProvider).map((m) => m.saveName).toList();

  ModFilterController filter() => container.read(modFilterProvider.notifier);

  group('filteredModsProvider', () {
    test('defaults to every mod of the selected type sorted by name', () {
      expect(names(), ['Alpha', 'mid', 'zeta']);
      container.read(selectedModTypeProvider.notifier).set(ModType.save);
      expect(names(), ['A save']);
      container.read(selectedModTypeProvider.notifier).set(ModType.savedObject);
      expect(names(), ['Obj']);
    });

    test('search is a case-insensitive contains on the name', () {
      filter().setQuery('ALP');
      expect(names(), ['Alpha']);
      filter().setQuery('  i  ');
      expect(names(), ['mid']);
      filter().setQuery('nothing');
      expect(names(), isEmpty);
      filter().setQuery('');
      expect(names(), hasLength(3));
    });

    test('folder filter toggles and is remembered per type', () {
      expect(container.read(availableFoldersProvider), ['Sub', 'Workshop']);
      filter().toggleFolder('Sub');
      expect(names(), ['Alpha']);
      expect(container.read(modFilterProvider).folders, {'Sub'});

      container.read(selectedModTypeProvider.notifier).set(ModType.save);
      expect(container.read(modFilterProvider).folders, isEmpty);
      expect(container.read(availableFoldersProvider), ['Saves']);
      expect(names(), ['A save']);
      filter().toggleFolder('Elsewhere');
      expect(names(), isEmpty);

      container.read(selectedModTypeProvider.notifier).set(ModType.mod);
      expect(container.read(modFilterProvider).folders, {'Sub'});
      expect(names(), ['Alpha']);
      filter().toggleFolder('Sub');
      expect(names(), hasLength(3));
    });

    test('backup status filter', () {
      filter().toggleBackupStatus(BackupStatus.none);
      expect(names(), ['mid']);
      filter().toggleBackupStatus(BackupStatus.upToDate);
      expect(names(), ['mid', 'zeta']);
      filter().toggleBackupStatus(BackupStatus.none);
      expect(names(), ['zeta']);
    });

    test('clearBackupStatuses drops only the backup statuses', () {
      filter()
        ..toggleBackupStatus(BackupStatus.upToDate)
        ..toggleFolder('Sub')
        ..setQuery('a');
      expect(names(), isEmpty);

      filter().clearBackupStatuses();

      final state = container.read(modFilterProvider);
      expect(state.backupStatuses, isEmpty);
      expect(state.folders, {'Sub'});
      expect(state.query, 'a');
      expect(names(), ['Alpha']);
    });

    test('complete and missing exclude each other', () {
      filter().toggleAssetFilter(AssetFilter.missing);
      expect(names(), ['mid', 'zeta']);
      filter().toggleAssetFilter(AssetFilter.complete);
      expect(container.read(modFilterProvider).assetFilters, {
        AssetFilter.complete,
      });
      expect(names(), ['Alpha']);
      filter().toggleAssetFilter(AssetFilter.complete);
      expect(container.read(modFilterProvider).assetFilters, isEmpty);
      expect(names(), hasLength(3));
    });

    test('audio and per-type asset filters', () {
      filter().toggleAssetFilter(AssetFilter.audio);
      expect(names(), ['Alpha']);
      filter().toggleAssetFilter(AssetFilter.audio);

      filter().toggleAssetFilter(AssetFilter.image);
      expect(names(), ['zeta']);
      filter().toggleAssetFilter(AssetFilter.model);
      expect(names(), ['zeta']);
      filter().toggleAssetFilter(AssetFilter.image);
      filter().toggleAssetFilter(AssetFilter.model);

      filter().toggleAssetFilter(AssetFilter.pdf);
      expect(names(), ['Alpha']);
      filter().toggleAssetFilter(AssetFilter.pdf);

      filter().toggleAssetFilter(AssetFilter.assetBundle);
      expect(names(), ['mid']);
      filter().toggleAssetFilter(AssetFilter.missing);
      expect(names(), ['mid']);
    });

    test('sort options', () {
      filter().setSort(ModSortOption.newest);
      // mid has no epoch and falls back to its 2024 mtime; the others use
      // their (tiny) epoch values.
      expect(names(), ['mid', 'Alpha', 'zeta']);
      filter().setSort(ModSortOption.recentlyUpdated);
      expect(names(), ['zeta', 'mid', 'Alpha']);
      filter().setSort(ModSortOption.missingAssets);
      expect(names(), ['mid', 'zeta', 'Alpha']);
      filter().setSort(ModSortOption.nameAsc);
      expect(names(), ['Alpha', 'mid', 'zeta']);
    });

    test('clear drops text and filters but keeps the sort', () {
      filter()
        ..setQuery('a')
        ..toggleFolder('Sub')
        ..toggleBackupStatus(BackupStatus.outOfDate)
        ..toggleAssetFilter(AssetFilter.pdf)
        ..setSort(ModSortOption.missingAssets);
      expect(container.read(modFilterProvider).isNotEmpty, isTrue);

      filter().clear();

      final state = container.read(modFilterProvider);
      expect(state.isEmpty, isTrue);
      expect(state.sort, ModSortOption.missingAssets);
      expect(names(), ['mid', 'zeta', 'Alpha']);
    });
  });

  group('selection', () {
    SelectionController selection() =>
        container.read(selectionProvider.notifier);

    test('select, toggle, selectMany and clear', () {
      selection().select(alpha.jsonPath);
      expect(container.read(selectionProvider), {alpha.jsonPath});
      selection().toggle(zeta.jsonPath);
      expect(container.read(selectionProvider), {
        alpha.jsonPath,
        zeta.jsonPath,
      });
      selection().toggle(alpha.jsonPath);
      expect(container.read(selectionProvider), {zeta.jsonPath});
      selection().selectMany([mid.jsonPath, save.jsonPath]);
      expect(container.read(selectionProvider), {mid.jsonPath, save.jsonPath});
      selection().clear();
      expect(container.read(selectionProvider), isEmpty);
    });

    test('selectedModProvider resolves exactly one selected mod', () {
      expect(container.read(selectedModProvider), isNull);
      selection().select(alpha.jsonPath);
      expect(container.read(selectedModProvider), alpha);
      selection().toggle(zeta.jsonPath);
      expect(container.read(selectedModProvider), isNull);
      selection().select('not/in/library.json');
      expect(container.read(selectedModProvider), isNull);
    });

    test('selectedModsProvider resolves across types and skips unknown', () {
      expect(container.read(selectedModsProvider), isEmpty);
      selection().selectMany([
        zeta.jsonPath,
        'not/in/library.json',
        save.jsonPath,
      ]);
      expect(container.read(selectedModsProvider), [zeta, save]);
    });
  });
}
