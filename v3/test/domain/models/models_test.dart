import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';

void main() {
  final ref = ModRef.fromPath(ModType.mod, p.join('Workshop', '123.json'));
  final backup = Backup(
    path: p.join('Backups', 'Name (123).ttsmod'),
    fileName: 'Name (123).ttsmod',
    folder: 'Backups',
    modified: DateTime.utc(2026, 3, 4),
    sizeBytes: 12897485,
    assetCount: 3,
  );
  const summary = AssetSummary(
    total: 5,
    present: 3,
    hasAudio: true,
    totalByType: {AssetType.image: 4, AssetType.audio: 1},
    presentByType: {AssetType.image: 2, AssetType.audio: 1},
  );
  final mod = Mod(
    ref: ref,
    saveName: 'Name',
    folder: 'Workshop',
    epochTime: 1700000000,
    modified: DateTime.utc(2026, 1, 2),
    sizeBytes: 1024,
    imagePath: null,
    audio: AudioVisibility.useGlobalSetting,
    summary: summary,
  );

  group('AssetSummary', () {
    test('empty is a const with no assets', () {
      expect(AssetSummary.empty.total, 0);
      expect(AssetSummary.empty.missing, 0);
      expect(AssetSummary.empty.isComplete, isTrue);
      expect(AssetSummary.empty.hasAudio, isFalse);
      expect(AssetSummary.empty.totalByType, isEmpty);
    });

    test('derived counts', () {
      expect(summary.missing, 2);
      expect(summary.isComplete, isFalse);
      expect(summary.totalOf(AssetType.image), 4);
      expect(summary.presentOf(AssetType.image), 2);
      expect(summary.missingOf(AssetType.image), 2);
      expect(summary.totalOf(AssetType.pdf), 0);
      expect(summary.missingOf(AssetType.pdf), 0);
    });

    test('equality is deep over the maps', () {
      const other = AssetSummary(
        total: 5,
        present: 3,
        hasAudio: true,
        totalByType: {AssetType.image: 4, AssetType.audio: 1},
        presentByType: {AssetType.image: 2, AssetType.audio: 1},
      );
      expect(summary, other);
    });
  });

  group('Mod', () {
    test('defaults: no backup, status none, no invalid urls', () {
      expect(mod.backup, isNull);
      expect(mod.backupStatus, BackupStatus.none);
      expect(mod.invalidUrls, isEmpty);
    });

    test('shortcuts and derived values', () {
      expect(mod.id, '123');
      expect(mod.jsonPath, ref.jsonPath);
      expect(mod.displayName, 'Name');
      expect(mod.missingCount, 2);
      expect(
        mod.savedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('displayName falls back to the id for a blank save name', () {
      expect(mod.copyWith(saveName: '').displayName, '123');
      expect(mod.copyWith(saveName: '   ').displayName, '123');
    });

    test('savedAt is null without an epoch time', () {
      expect(mod.copyWith(epochTime: null).savedAt, isNull);
    });

    test('copyWith can set and clear the backup', () {
      final withBackup = mod.copyWith(
        backup: backup,
        backupStatus: BackupStatus.upToDate,
      );
      expect(withBackup.backup, backup);
      expect(withBackup.backupStatus, BackupStatus.upToDate);

      final cleared = withBackup.copyWith(
        backup: null,
        backupStatus: BackupStatus.none,
      );
      expect(cleared.backup, isNull);
      expect(cleared.backupStatus, BackupStatus.none);
    });
  });

  group('Asset', () {
    test('exists follows path', () {
      const missing = Asset(
        url: 'https://x/y.png',
        type: AssetType.image,
        fileKey: 'httpsxypng',
        path: null,
      );
      expect(missing.exists, isFalse);
      expect(missing.invalid, isFalse);
      expect(
        missing.copyWith(path: p.join('Images', 'httpsxypng.png')).exists,
        isTrue,
      );
    });
  });

  group('Backup', () {
    test('fileSizeLabel uses mebibytes with one decimal', () {
      expect(backup.fileSizeLabel, '12.3 MB');
      expect(backup.copyWith(sizeBytes: 0).fileSizeLabel, '0.0 MB');
    });

    test('hasMatchingMod follows matchingModPath', () {
      expect(backup.hasMatchingMod, isFalse);
      expect(
        backup.copyWith(matchingModPath: ref.jsonPath).hasMatchingMod,
        isTrue,
      );
    });
  });

  group('ModFilter', () {
    test('empty has no criteria and the default sort', () {
      expect(ModFilter.empty.isEmpty, isTrue);
      expect(ModFilter.empty.isNotEmpty, isFalse);
      expect(ModFilter.empty.sort, ModSortOption.nameAsc);
      expect(const ModFilter(), ModFilter.empty);
    });

    test('isEmpty ignores sort but not the other fields', () {
      expect(
        ModFilter.empty.copyWith(sort: ModSortOption.newest).isEmpty,
        isTrue,
      );
      expect(ModFilter.empty.copyWith(query: ' ').isEmpty, isTrue);
      expect(ModFilter.empty.copyWith(query: 'a').isEmpty, isFalse);
      expect(ModFilter.empty.copyWith(folders: {'Workshop'}).isEmpty, isFalse);
      expect(
        ModFilter.empty
            .copyWith(backupStatuses: {BackupStatus.outOfDate})
            .isEmpty,
        isFalse,
      );
      expect(
        ModFilter.empty.copyWith(assetFilters: {AssetFilter.missing}).isEmpty,
        isFalse,
      );
    });

    test('sets compare by content', () {
      expect(
        const ModFilter(folders: {'a', 'b'}),
        const ModFilter(folders: {'b', 'a'}),
      );
    });
  });
}
