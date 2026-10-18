import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/backup_rules.dart';

void main() {
  group('sanitizeFileName', () {
    test('replaces every character invalid on Windows with an underscore', () {
      expect(sanitizeFileName(r'a:b/c\d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
    });

    test('trims whitespace and strips leading and trailing dots', () {
      expect(sanitizeFileName('  name  '), 'name');
      expect(sanitizeFileName('..hidden..'), 'hidden');
      expect(sanitizeFileName(' .name. '), 'name');
    });

    test('keeps interior dots and other punctuation', () {
      expect(
        sanitizeFileName('v1.2 (final) [x] & more!'),
        'v1.2 (final) [x] & more!',
      );
    });

    test('is a no-op for already-valid names', () {
      expect(
        sanitizeFileName('Gloomhaven (123).ttsmod'),
        'Gloomhaven (123).ttsmod',
      );
    });
  });

  group('backupFileName', () {
    test('workshop mod with a numeric id includes the id', () {
      expect(
        backupFileName(saveName: 'Gloomhaven', modId: '123', type: ModType.mod),
        'Gloomhaven (123).ttsmod',
      );
    });

    test('workshop mod with a non-numeric id drops the id', () {
      expect(
        backupFileName(
          saveName: 'Dice Throne',
          modId: 'Dice Throne',
          type: ModType.mod,
        ),
        'Dice Throne.ttsmod',
      );
    });

    test('forceIncludeId keeps a non-numeric id for workshop mods', () {
      expect(
        backupFileName(
          saveName: 'Dice Throne',
          modId: 'Dice Throne',
          type: ModType.mod,
          forceIncludeId: true,
        ),
        'Dice Throne (Dice Throne).ttsmod',
      );
    });

    test('forceIncludeId changes nothing for a numeric id', () {
      expect(
        backupFileName(
          saveName: 'Gloomhaven',
          modId: '123',
          type: ModType.mod,
          forceIncludeId: true,
        ),
        'Gloomhaven (123).ttsmod',
      );
    });

    test('saves always include the id, numeric or not', () {
      expect(
        backupFileName(
          saveName: 'My Game',
          modId: 'TS_Save_1',
          type: ModType.save,
        ),
        'My Game (TS_Save_1).ttsmod',
      );
      expect(
        backupFileName(saveName: 'My Game', modId: '7', type: ModType.save),
        'My Game (7).ttsmod',
      );
    });

    test(
      'saved objects use the "(saved object)" suffix regardless of force',
      () {
        for (final force in [false, true]) {
          expect(
            backupFileName(
              saveName: 'Token Bag',
              modId: 'Token Bag',
              type: ModType.savedObject,
              forceIncludeId: force,
            ),
            'Token Bag (saved object).ttsmod',
          );
        }
      },
    );

    test('the result is sanitized', () {
      expect(
        backupFileName(saveName: 'A/B: C?', modId: '1', type: ModType.mod),
        'A_B_ C_ (1).ttsmod',
      );
      expect(
        backupFileName(saveName: '..dots..', modId: 'x', type: ModType.mod),
        'dots...ttsmod',
      );
      expect(
        backupFileName(saveName: ' .lead', modId: '1', type: ModType.mod),
        'lead (1).ttsmod',
      );
    });
  });

  group('backupFileNameCandidates', () {
    final numeric = ModRef.fromPath(
      ModType.mod,
      p.join('Workshop', '123.json'),
    );
    final named = ModRef.fromPath(
      ModType.mod,
      p.join('Workshop', 'Dice Throne.json'),
    );
    final save = ModRef.fromPath(ModType.save, p.join('Saves', 'TS_1.json'));
    final object = ModRef.fromPath(
      ModType.savedObject,
      p.join('Saves', 'Saved Objects', 'Bag.json'),
    );

    test('without force there is exactly one candidate', () {
      expect(backupFileNameCandidates(ref: numeric, saveName: 'G'), [
        'G (123).ttsmod',
      ]);
      expect(backupFileNameCandidates(ref: named, saveName: 'Dice Throne'), [
        'Dice Throne.ttsmod',
      ]);
    });

    test('with force a non-numeric mod tries the forced name first', () {
      expect(
        backupFileNameCandidates(
          ref: named,
          saveName: 'Dice Throne',
          forceIncludeId: true,
        ),
        ['Dice Throne (Dice Throne).ttsmod', 'Dice Throne.ttsmod'],
      );
    });

    test('with force a numeric mod still has one candidate', () {
      expect(
        backupFileNameCandidates(
          ref: numeric,
          saveName: 'G',
          forceIncludeId: true,
        ),
        ['G (123).ttsmod'],
      );
    });

    test('force does not apply to saves and saved objects', () {
      expect(
        backupFileNameCandidates(
          ref: save,
          saveName: 'S',
          forceIncludeId: true,
        ),
        ['S (TS_1).ttsmod'],
      );
      expect(
        backupFileNameCandidates(
          ref: object,
          saveName: 'Bag',
          forceIncludeId: true,
        ),
        ['Bag (saved object).ttsmod'],
      );
    });
  });

  group('backupStatusFor', () {
    const epoch = 1700000000;
    Backup backupAt(int seconds, {int assetCount = 10}) => Backup(
      path: 'x.ttsmod',
      fileName: 'x.ttsmod',
      folder: 'Backups',
      modified: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
      sizeBytes: 1,
      assetCount: assetCount,
    );

    test('no backup is none', () {
      expect(
        backupStatusFor(backup: null, epochTime: epoch, presentAssetCount: 10),
        BackupStatus.none,
      );
    });

    test('newer backup with matching count is up to date', () {
      expect(
        backupStatusFor(
          backup: backupAt(epoch + 1),
          epochTime: epoch,
          presentAssetCount: 10,
        ),
        BackupStatus.upToDate,
      );
    });

    test('newer backup with a different count is a mismatch', () {
      expect(
        backupStatusFor(
          backup: backupAt(epoch + 1),
          epochTime: epoch,
          presentAssetCount: 9,
        ),
        BackupStatus.assetCountMismatch,
      );
    });

    test('older backup is out of date even when counts differ', () {
      expect(
        backupStatusFor(
          backup: backupAt(epoch - 1),
          epochTime: epoch,
          presentAssetCount: 0,
        ),
        BackupStatus.outOfDate,
      );
    });

    test('the comparison is strictly greater at whole seconds (v2)', () {
      final sameSecond = backupAt(epoch).copyWith(
        modified: DateTime.fromMillisecondsSinceEpoch(epoch * 1000 + 999),
      );
      expect(
        backupStatusFor(
          backup: sameSecond,
          epochTime: epoch,
          presentAssetCount: 10,
        ),
        BackupStatus.outOfDate,
      );
    });

    test('without a save date only the counts matter', () {
      expect(
        backupStatusFor(
          backup: backupAt(0),
          epochTime: null,
          presentAssetCount: 10,
        ),
        BackupStatus.upToDate,
      );
      expect(
        backupStatusFor(
          backup: backupAt(0),
          epochTime: null,
          presentAssetCount: 11,
        ),
        BackupStatus.assetCountMismatch,
      );
    });
  });
}
