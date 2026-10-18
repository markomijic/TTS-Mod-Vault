// Deleting and renaming a backup from the Backups tab (context menu and
// panel) and deleting from the mod context menu.

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_context_menu.dart';
import 'package:tts_mod_vault/core/result/result.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_grid_card.dart';
import 'package:tts_mod_vault/features/backups/presentation/rename_backup_dialog.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_grid_card.dart';

import '../../library/presentation/dialogs/dialog_test_harness.dart'
    show buttonEnabled, fieldLabelled, fieldText;
import '../../library/presentation/presentation_test_harness.dart';
import '../backups_test_harness.dart';
import 'fake_backup_service.dart';

void main() {
  late FixtureLibrary library;
  late FixtureBackups backups;
  late ProviderContainer container;
  late FakeBackupService service;

  setUpAll(() {
    library = FixtureLibrary.create();
    backups = FixtureBackups(library);
  });
  tearDownAll(() => library.delete());

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

  Finder card(String fileName) => find.ancestor(
    of: find.text(fileName),
    matching: find.byType(BackupGridCard),
  );

  Finder menuItem(String label) => find.descendant(
    of: find.byType(PopupMenuItem<MenuAction>),
    matching: find.text(label),
  );

  Future<void> pumpBackupsTab(WidgetTester tester) async {
    await pumpLibraryPage(tester, container);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<LibraryTab>),
        matching: find.text('Backups'),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('delete backup', () {
    testWidgets('context menu asks, Cancel keeps the archive', (tester) async {
      await pumpBackupsTab(tester);

      await tester.tap(card('Gamma Mod.ttsmod'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(menuItem('Delete backup'));
      await tester.pumpAndSettle();

      expect(find.text('Delete backup?'), findsOneWidget);
      expect(find.textContaining('Gamma Mod.ttsmod'), findsWidgets);
      expect(find.textContaining('deleted permanently'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(service.deleteCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('panel Delete backup confirms and deletes', (tester) async {
      await pumpBackupsTab(tester);

      await tester.tap(card('Gamma Mod.ttsmod'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(service.deleteCalls.map((b) => b.path), [backups.gamma.path]);
      expect(find.text('Gamma Mod.ttsmod deleted'), findsOneWidget);
    });

    testWidgets('Delete key confirms and deletes the selected backup', (
      tester,
    ) async {
      await pumpBackupsTab(tester);

      // Nothing selected: nothing happens.
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(card('Gamma Mod.ttsmod'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.text('Delete backup?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(service.deleteCalls.map((b) => b.path), [backups.gamma.path]);
      expect(find.text('Gamma Mod.ttsmod deleted'), findsOneWidget);
    });

    testWidgets('a failure shows its message', (tester) async {
      service.deleteResult = const Err(Failure('Could not delete backup'));
      await pumpBackupsTab(tester);

      await tester.tap(card('Gamma Mod.ttsmod'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(menuItem('Delete backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Could not delete backup'), findsOneWidget);
    });

    testWidgets('mod context menu Delete backup deletes the mod\'s backup', (
      tester,
    ) async {
      final modsContainer = ProviderContainer.test(
        overrides: [
          ...libraryPageOverrides(
            library: () => SpyLibraryController(library.state),
          ),
          fakeBackupServiceOverride(),
        ],
      );
      final modsService =
          modsContainer.read(backupServiceProvider) as FakeBackupService;
      await pumpLibraryPage(tester, modsContainer);

      await tester.tap(
        find.ancestor(
          of: find.text('Beta Mod'),
          matching: find.byType(ModsGridCard),
        ),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete backup'));
      await tester.pumpAndSettle();
      expect(find.text('Delete backup?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(modsService.deleteCalls.map((b) => b.path), [
        library.beta.backup!.path,
      ]);
      expect(find.text('Beta Mod.ttsmod deleted'), findsOneWidget);
    });
  });

  group('rename backup', () {
    testWidgets('the dialog is prefilled and Rename is disabled until the '
        'name changes', (tester) async {
      await pumpBackupsTab(tester);

      await tester.tap(card('Alpha Mod.ttsmod'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rename backup…'));
      await tester.pumpAndSettle();

      expect(find.byType(RenameBackupDialog), findsOneWidget);
      expect(fieldText(tester, 'File name'), 'Alpha Mod');
      expect(buttonEnabled(tester, 'Rename'), isFalse);

      await tester.enterText(fieldLabelled('File name'), '   ');
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      expect(buttonEnabled(tester, 'Rename'), isFalse);

      await tester.enterText(fieldLabelled('File name'), 'Alpha Renamed');
      await tester.pumpAndSettle();
      expect(buttonEnabled(tester, 'Rename'), isTrue);

      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(service.renameCalls, hasLength(1));
      final (backup, name) = service.renameCalls.single;
      expect(backup.path, backups.alpha.path);
      expect(name, 'Alpha Renamed');
      expect(find.byType(RenameBackupDialog), findsNothing);
      expect(find.text('Renamed to "Alpha Renamed.ttsmod"'), findsOneWidget);
    });

    testWidgets('context menu opens the dialog; a failure stays inline', (
      tester,
    ) async {
      service.renameFailure = const Failure('A file with that name exists');
      await pumpBackupsTab(tester);

      await tester.tap(card('Beta Mod.ttsmod'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(menuItem('Rename backup…'));
      await tester.pumpAndSettle();
      expect(find.byType(RenameBackupDialog), findsOneWidget);

      await tester.enterText(fieldLabelled('File name'), 'Taken');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(find.byType(RenameBackupDialog), findsOneWidget);
      expect(find.text('A file with that name exists'), findsOneWidget);
      expect(service.renameCalls.single.$2, 'Taken');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(RenameBackupDialog), findsNothing);
    });
  });
}
