// Importing backups from the sidebar (file picker), the Backups tab
// (context menu, panel button, "Import selected") and the mod context
// menu, with the JSON conflict dialog and the results dialog.

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/widgets/app_context_menu.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_grid_card.dart';
import 'package:tts_mod_vault/features/backups/presentation/file_picker_service.dart';
import 'package:tts_mod_vault/features/backups/presentation/import_results_dialog.dart';
import 'package:tts_mod_vault/features/backups/presentation/json_conflict_dialog.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart'
    show modDateFormat;
import 'package:tts_mod_vault/features/library/presentation/mods_grid_card.dart';

import '../../library/presentation/presentation_test_harness.dart';
import '../backups_test_harness.dart';
import 'fake_backup_service.dart';
import 'fake_file_picker_service.dart';
import 'shell_test_harness.dart';

void main() {
  late FixtureLibrary library;
  late FixtureBackups backups;

  setUpAll(() {
    library = FixtureLibrary.create();
    backups = FixtureBackups(library);
  });
  tearDownAll(() => library.delete());

  final localSaved = DateTime(2024, 3, 1, 12);
  final backupSaved = DateTime(2024, 2, 1, 12);
  final conflict = JsonImportConflict(
    jsonFileName: '100001.json',
    localEpoch: localSaved.millisecondsSinceEpoch ~/ 1000,
    backupEpoch: backupSaved.millisecondsSinceEpoch ~/ 1000,
    existingAssetCount: 4,
    backupAssetCount: 1,
    targetPath: p.join(fixtureDirectories.workshopDir, '100001.json'),
  );

  Finder card(String fileName) => find.ancestor(
    of: find.text(fileName),
    matching: find.byType(BackupGridCard),
  );

  Finder menuItem(String label) => find.descendant(
    of: find.byType(PopupMenuItem<MenuAction>),
    matching: find.text(label),
  );

  Finder segment(String label) => find.descendant(
    of: find.byType(SegmentedButton<LibraryTab>),
    matching: find.text(label),
  );

  group('Backups tab', () {
    late ProviderContainer container;
    late FakeBackupService service;

    setUp(() {
      container = ProviderContainer.test(
        overrides: [
          ...libraryPageOverrides(
            library: () => SpyLibraryController(backups.state),
          ),
          fakeBackupServiceOverride(),
        ],
      );
      service = container.read(backupServiceProvider) as FakeBackupService;
    });

    Future<void> pumpBackupsTab(WidgetTester tester) async {
      await pumpLibraryPage(tester, container);
      await tester.tap(segment('Backups'));
      await tester.pumpAndSettle();
    }

    testWidgets('context menu Import backup targets the matching mod', (
      tester,
    ) async {
      await pumpBackupsTab(tester);

      await tester.tap(card('Alpha Mod.ttsmod'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(menuItem('Import backup'));
      await tester.pumpAndSettle();

      expect(service.importCalls, hasLength(1));
      final (paths, targetJsonDir) = service.importCalls.single;
      expect(paths, [backups.alpha.path]);
      expect(targetJsonDir, p.dirname(library.alpha.jsonPath));
      expect(find.text('Imported 1 backup'), findsOneWidget);
      expect(find.byType(ImportResultsDialog), findsNothing);
    });

    testWidgets('panel Import backup of an unmatched backup has no target', (
      tester,
    ) async {
      await pumpBackupsTab(tester);

      await tester.tap(card('Old Thing.ttsmod'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Import backup'));
      await tester.pumpAndSettle();

      final (paths, targetJsonDir) = service.importCalls.single;
      expect(paths, [backups.oldThing.path]);
      expect(targetJsonDir, isNull);
    });

    testWidgets('Import selected imports the selection', (tester) async {
      await pumpBackupsTab(tester);

      await tester.tap(card('Beta Mod.ttsmod'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(card('Zeta Pack.ttsmod'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import selected (2)'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      final (paths, targetJsonDir) = service.importCalls.single;
      expect(
        paths,
        unorderedEquals([backups.beta.path, backups.zetaPack.path]),
      );
      expect(targetJsonDir, isNull);
      expect(find.text('Imported 2 backups'), findsOneWidget);
    });

    testWidgets('Import selected with no selection confirms, then imports '
        'every listed backup', (tester) async {
      await pumpBackupsTab(tester);

      await tester.tap(find.text('Import selected (5)'));
      await tester.pumpAndSettle();
      expect(find.text('Import all listed backups?'), findsOneWidget);
      expect(find.textContaining('5 backups will be imported'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.importCalls, isEmpty);

      await tester.tap(find.text('Import selected (5)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(service.importCalls.single.$1, hasLength(5));
      expect(find.text('Imported 5 backups'), findsOneWidget);
    });

    group('JSON conflict dialog', () {
      Future<void> importAlpha(WidgetTester tester) async {
        await pumpBackupsTab(tester);
        await tester.tap(card('Alpha Mod.ttsmod'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Import backup'));
        await tester.pumpAndSettle();
      }

      testWidgets('shows both files and Keep current keeps the JSON', (
        tester,
      ) async {
        service.conflict = conflict;
        await importAlpha(tester);

        expect(find.byType(JsonConflictDialog), findsOneWidget);
        expect(
          find.text('Backup is older than your current file'),
          findsOneWidget,
        );
        expect(find.textContaining('"100001.json"'), findsOneWidget);
        expect(
          find.text(
            'Your current file: ${modDateFormat.format(localSaved)}'
            '\n4 asset files',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Backup file: ${modDateFormat.format(backupSaved)}\n1 asset file',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('asset files from the backup are imported'),
          findsOneWidget,
        );

        await tester.tap(find.text('Keep current JSON file'));
        await tester.pumpAndSettle();

        expect(service.conflictChoices, [JsonConflictChoice.keepCurrent]);
        expect(find.text('Imported 1 backup'), findsOneWidget);
        expect(find.byType(ImportResultsDialog), findsNothing);
      });

      testWidgets('Use backup JSON file overwrites it', (tester) async {
        service.conflict = conflict;
        await importAlpha(tester);

        await tester.tap(find.text('Use backup JSON file'));
        await tester.pumpAndSettle();

        expect(service.conflictChoices, [JsonConflictChoice.useBackup]);
        expect(find.text('Imported 1 backup'), findsOneWidget);
      });

      testWidgets('Cancel skips the archive and shows the results', (
        tester,
      ) async {
        service.conflict = conflict;
        await importAlpha(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(service.conflictChoices, [JsonConflictChoice.cancel]);
        expect(find.byType(ImportResultsDialog), findsOneWidget);
        expect(find.text('Imported 0 of 1 backups, 1 skipped'), findsOneWidget);
        expect(find.text('Alpha Mod.ttsmod'), findsWidgets);
        expect(find.text('Skipped'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(ImportResultsDialog), findsNothing);
      });
    });

    testWidgets('a failed archive is listed in the results dialog', (
      tester,
    ) async {
      service.importErrors = {backups.beta.path: 'not a zip'};
      service.notReached = {backups.zetaPack.path};
      service.importCancelled = true;
      await pumpBackupsTab(tester);

      await tester.tap(find.text('Import selected (5)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportResultsDialog), findsOneWidget);
      expect(
        find.text('Imported 3 of 5 backups, 1 failed, 1 skipped'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The import was cancelled before every archive was processed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Failed: not a zip'), findsOneWidget);
      expect(find.text('Not processed (cancelled)'), findsOneWidget);
      expect(find.text('Imported, 3 asset files'), findsNWidgets(3));
    });

    testWidgets('a refused start shows the already-running snack bar', (
      tester,
    ) async {
      service.alreadyRunning = true;
      await pumpBackupsTab(tester);

      await tester.tap(card('Alpha Mod.ttsmod'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Import backup'));
      await tester.pumpAndSettle();

      expect(find.text('An operation is already running'), findsOneWidget);
    });
  });

  group('mod context menu', () {
    testWidgets('Import backup imports the mod\'s backup into its folder', (
      tester,
    ) async {
      final container = ProviderContainer.test(
        overrides: [
          ...libraryPageOverrides(
            library: () => SpyLibraryController(library.state),
          ),
          fakeBackupServiceOverride(),
        ],
      );
      final service =
          container.read(backupServiceProvider) as FakeBackupService;
      await pumpLibraryPage(tester, container);

      await tester.tap(
        find.ancestor(
          of: find.text('Beta Mod'),
          matching: find.byType(ModsGridCard),
        ),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();

      final (paths, targetJsonDir) = service.importCalls.single;
      expect(paths, [library.beta.backup!.path]);
      expect(targetJsonDir, p.dirname(library.beta.jsonPath));
      expect(find.text('Imported 1 backup'), findsOneWidget);
    });
  });

  group('sidebar Import backups', () {
    late FakeFilePickerService filePicker;
    late ProviderContainer container;
    late FakeBackupService service;

    setUp(() {
      filePicker = FakeFilePickerService();
      container = shellContainer(
        backups.state,
        overrides: [
          fakeBackupServiceOverride(),
          filePickerServiceProvider.overrideWithValue(filePicker),
        ],
      );
      service = container.read(backupServiceProvider) as FakeBackupService;
    });

    testWidgets('picks archives in the backups folder and imports them', (
      tester,
    ) async {
      final a = p.join(fixtureDirectories.backupsDir, 'a.ttsmod');
      final b = p.join(fixtureDirectories.backupsDir, 'b.ttsmod');
      filePicker.ttsmodFiles = [a, b];
      await pumpShell(tester, container);

      await tapSidebar(tester, 'Import backups');

      expect(filePicker.ttsmodInitialDirectories, [
        fixtureDirectories.backupsDir,
      ]);
      final (paths, targetJsonDir) = service.importCalls.single;
      expect(paths, [a, b]);
      expect(targetJsonDir, isNull);
      expect(find.text('Imported 2 backups'), findsOneWidget);
    });

    testWidgets('a cancelled picker imports nothing', (tester) async {
      await pumpShell(tester, container);

      await tapSidebar(tester, 'Import backups');

      expect(service.importCalls, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a picker failure is reported', (tester) async {
      filePicker.error = Exception('no dialog');
      await pumpShell(tester, container);

      await tapSidebar(tester, 'Import backups');

      expect(service.importCalls, isEmpty);
      expect(find.text('Could not open the file picker'), findsOneWidget);
    });
  });
}
