// The Workshop results dialogs group items by status with counts.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_results.dart';
import 'package:tts_mod_vault/features/workshop/presentation/workshop_results_dialog.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations_en.dart';

import '../../images_viewer/themed_app.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('WorkshopUpdateResultsDialog', () {
    final batch = WorkshopUpdateBatchResult(const [
      WorkshopUpdateResult(
        id: '1',
        modName: 'Alpha',
        jsonPath: 'a.json',
        status: WorkshopUpdateStatus.updated,
      ),
      WorkshopUpdateResult(
        id: '2',
        modName: 'Beta',
        jsonPath: 'b.json',
        status: WorkshopUpdateStatus.upToDate,
      ),
      WorkshopUpdateResult(
        id: '3',
        modName: 'Gamma',
        jsonPath: 'c.json',
        status: WorkshopUpdateStatus.upToDate,
      ),
      WorkshopUpdateResult(
        id: '4',
        modName: 'Delta',
        jsonPath: 'd.json',
        status: WorkshopUpdateStatus.failed,
        itemStatus: WorkshopItemStatus.unlisted,
        error: 'the item is unlisted or private',
      ),
    ]);

    testWidgets('groups updated, up to date and failed with counts', (
      tester,
    ) async {
      await pumpThemedApp(
        tester,
        home: Scaffold(body: WorkshopUpdateResultsDialog(result: batch)),
      );

      expect(find.text('Update complete'), findsOneWidget);
      expect(find.text('Updated (1)'), findsOneWidget);
      expect(find.text('Already up to date (2)'), findsOneWidget);
      expect(find.text('Failed (1)'), findsOneWidget);
      expect(find.text('Cancelled (0)'), findsNothing);
      for (final name in ['Alpha', 'Beta', 'Gamma', 'Delta']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('the item is unlisted or private'), findsOneWidget);
      // Summary tiles: one count per section.
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('a cancelled batch gets the cancelled title and section', (
      tester,
    ) async {
      final cancelled = WorkshopUpdateBatchResult(const [
        WorkshopUpdateResult(
          id: '1',
          modName: 'Alpha',
          jsonPath: 'a.json',
          status: WorkshopUpdateStatus.updated,
        ),
        WorkshopUpdateResult(
          id: '2',
          modName: 'Beta',
          jsonPath: 'b.json',
          status: WorkshopUpdateStatus.cancelled,
        ),
      ]);
      await pumpThemedApp(
        tester,
        home: Scaffold(body: WorkshopUpdateResultsDialog(result: cancelled)),
      );
      expect(find.text('Update cancelled'), findsOneWidget);
      expect(find.text('Cancelled (1)'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  group('WorkshopDownloadResultsDialog', () {
    testWidgets('lists downloaded items by title and failed ones with the '
        'reason', (tester) async {
      final batch = WorkshopDownloadBatchResult(const [
        WorkshopDownloadResult(
          id: '10',
          title: 'Chess',
          status: WorkshopItemStatus.ok,
          jsonPath: '10.json',
        ),
        WorkshopDownloadResult(id: '11', status: WorkshopItemStatus.notFound),
        WorkshopDownloadResult(
          id: '12',
          title: 'Go',
          status: WorkshopItemStatus.ok,
          error: 'Failed to download the Workshop file (500)',
        ),
      ]);
      await pumpThemedApp(
        tester,
        home: Scaffold(body: WorkshopDownloadResultsDialog(result: batch)),
      );

      expect(find.text('Workshop download complete'), findsOneWidget);
      expect(find.text('Downloaded (1)'), findsOneWidget);
      expect(find.text('Failed (2)'), findsOneWidget);
      expect(find.text('Chess'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('The item is not on the Workshop'), findsOneWidget);
      expect(find.text('Go (12)'), findsOneWidget);
      expect(
        find.text('Failed to download the Workshop file (500)'),
        findsOneWidget,
      );
    });
  });

  test('workshopResultsText lists only non-empty sections', () {
    final text = workshopResultsText(l10n, 'Title', const [
      ResultSection(
        title: 'Updated',
        icon: Icons.check,
        color: Colors.transparent,
        lines: [(name: 'Alpha', detail: null)],
      ),
      ResultSection(
        title: 'Failed',
        icon: Icons.error,
        color: Colors.transparent,
        lines: [],
      ),
      ResultSection(
        title: 'Cancelled',
        icon: Icons.cancel,
        color: Colors.transparent,
        lines: [(name: 'Beta', detail: 'why')],
      ),
    ]);
    expect(text, 'Title\n\nUpdated (1)\nAlpha\n\nCancelled (1)\nBeta\n    why');
  });
}
