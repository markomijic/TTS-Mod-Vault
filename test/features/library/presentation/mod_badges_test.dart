// The backup badge tooltip: status line, both dates (the mod's save date
// against the backup date, as 2.x showed), the archive's asset count and
// the mismatch line; the missing badge with and without dead URLs.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations_en.dart';

import '../../images_viewer/themed_app.dart';
import 'presentation_test_harness.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('shows the mod save date and the backup date', () {
    final mod = fixtureMod(
      'Alpha',
      id: '1',
      epoch: DateTime(2024, 3, 5, 9, 15).millisecondsSinceEpoch ~/ 1000,
      backupStatus: BackupStatus.upToDate,
      backupAssetCount: 4,
    );

    final lines = backupTooltip(l10n, mod).split('\n');

    expect(lines, [
      'Up to date',
      'Mod saved: ${formatModDate('en', DateTime(2024, 3, 5, 9, 15))}',
      'Backup: ${formatModDate('en', mod.backup!.modified)}',
      '4 assets in backup',
    ]);
  });

  test('falls back to the file mtime when the JSON has no date', () {
    final modified = DateTime(2024, 6, 1, 8);
    final mod = fixtureMod(
      'Beta',
      id: '2',
      modified: modified,
      backupStatus: BackupStatus.outOfDate,
    );

    expect(
      backupTooltip(l10n, mod),
      contains('Mod saved: ${formatModDate('en', modified)}'),
    );
  });

  test('a mismatch adds the mod\'s own count; no backup means status only', () {
    final mismatch = fixtureMod(
      'Gamma',
      id: '3',
      total: 3,
      present: 2,
      backupStatus: BackupStatus.assetCountMismatch,
      backupAssetCount: 5,
    );
    expect(
      backupTooltip(l10n, mismatch).split('\n').last,
      'The mod has 2 asset files on disk',
    );

    final none = fixtureMod('Delta', id: '4');
    expect(backupTooltip(l10n, none), 'No backup');
  });

  group('MissingCountBadge', () {
    Future<Object?> pumpBadge(WidgetTester tester, Mod mod) => pumpThemedApp(
      tester,
      home: Scaffold(body: MissingCountBadge(mod: mod)),
    );

    testWidgets('shows the missing count', (tester) async {
      await pumpBadge(tester, fixtureMod('A', id: '1', total: 5, present: 2));
      expect(find.text('3 missing'), findsOneWidget);
    });

    testWidgets('adds the invalid count when missing URLs are dead', (
      tester,
    ) async {
      final mod = fixtureMod('A', id: '1', total: 5, present: 2);
      await pumpBadge(
        tester,
        mod.copyWith(summary: mod.summary.copyWith(missingInvalid: 3)),
      );
      expect(find.text('3 missing, 3 invalid'), findsOneWidget);
    });

    testWidgets('shows nothing when every file is on disk', (tester) async {
      await pumpBadge(tester, fixtureMod('A', id: '1', total: 2, present: 2));
      expect(find.byType(Text), findsNothing);
    });
  });
}
