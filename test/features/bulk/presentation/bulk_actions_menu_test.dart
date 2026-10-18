// The bulk actions menu and the multi-select buttons: target counting
// (selection vs. current filters), each item's dialog and the call it
// makes on the BulkService with the dialog's choices, the Workshop item's
// gating, and the results shown afterwards.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/multi_select_view.dart';
import 'package:tts_mod_vault/features/backups/presentation/file_picker_service.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_backup_dialog.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_delete_assets_dialog.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_failures_dialog.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_targets.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_url_check_results_dialog.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart'
    show DownloadBatchResult, DownloadOutcome, DownloadStatus, UrlCheckResult;
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/bulk_actions_button.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/features/workshop/presentation/workshop_results_dialog.dart';

import '../../backups/presentation/fake_file_picker_service.dart';
import '../../library/presentation/presentation_test_harness.dart';
import '../../operations/presentation/fake_operation_runner.dart';
import '../../startup/startup_test_helpers.dart' show FakeDirectoryPicker;
import 'fake_bulk_service.dart';

void main() {
  late FixtureLibrary library;
  late ProviderContainer container;
  late FakeBulkService service;
  late FakeFilePickerService filePicker;
  late FakeDirectoryPicker directoryPicker;

  setUpAll(() => library = FixtureLibrary.create());
  tearDownAll(() => library.delete());

  setUp(() {
    filePicker = FakeFilePickerService();
    directoryPicker = FakeDirectoryPicker([]);
    container = ProviderContainer.test(
      overrides: [
        ...libraryPageOverrides(
          library: () => SpyLibraryController(library.state),
        ),
        fakeBulkServiceOverride(),
        filePickerServiceProvider.overrideWithValue(filePicker),
        directoryPickerProvider.overrideWithValue(directoryPicker),
      ],
    );
    service = container.read(bulkServiceProvider) as FakeBulkService;
  });

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(BulkActionsButton));
    await tester.pumpAndSettle();
  }

  Future<void> pickItem(WidgetTester tester, String label) async {
    await openMenu(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, label));
    await tester.pumpAndSettle();
  }

  VoidCallback? itemCallback(WidgetTester tester, String label) => tester
      .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, label))
      .onPressed;

  Set<String> paths(List<Mod> mods) => {for (final mod in mods) mod.jsonPath};

  group('targets', () {
    testWidgets('nothing selected: the filtered list, header says so', (
      tester,
    ) async {
      await pumpLibraryPage(tester, container);
      expect(find.text('Bulk actions (5)'), findsOneWidget);
      await openMenu(tester);

      expect(find.text('5 mods (current filters)'), findsOneWidget);
      for (final label in [
        'Download',
        'Backup',
        'Download & backup',
        'Update from Steam Workshop',
        'Delete assets',
        'Check for invalid URLs',
        'Update URLs',
        'Import backups',
      ]) {
        expect(find.widgetWithText(MenuItemButton, label), findsOneWidget);
        expect(itemCallback(tester, label), isNotNull, reason: label);
      }
    });

    testWidgets('two or more selected: the selection', (tester) async {
      container.read(selectionProvider.notifier).selectMany([
        library.beta.jsonPath,
        library.delta.jsonPath,
      ]);
      await pumpLibraryPage(tester, container);

      expect(find.text('Bulk actions (2)'), findsOneWidget);
      final targets = container.read(bulkTargetsProvider);
      expect(targets.fromSelection, isTrue);
      expect(paths(targets.mods), paths([library.beta, library.delta]));

      await openMenu(tester);
      expect(find.text('2 mods (selection)'), findsOneWidget);
    });

    testWidgets('one selected still means the filtered list', (tester) async {
      container.read(selectionProvider.notifier).select(library.beta.jsonPath);
      await pumpLibraryPage(tester, container);
      expect(find.text('Bulk actions (5)'), findsOneWidget);
      expect(container.read(bulkTargetsProvider).fromSelection, isFalse);
    });

    testWidgets('Workshop update is disabled for saves', (tester) async {
      await pumpLibraryPage(tester, container);
      await tester.tap(find.text('Saves'));
      await tester.pumpAndSettle();
      expect(container.read(libraryTabProvider), LibraryTab.saves);

      await openMenu(tester);
      expect(find.text('1 save (current filters)'), findsOneWidget);
      expect(itemCallback(tester, 'Update from Steam Workshop'), isNull);
      expect(itemCallback(tester, 'Download'), isNotNull);
    });

    testWidgets('the button is disabled while an operation runs', (
      tester,
    ) async {
      container = ProviderContainer.test(
        overrides: [
          ...libraryPageOverrides(
            library: () => SpyLibraryController(library.state),
          ),
          fakeBulkServiceOverride(),
          operationRunnerProvider.overrideWith(
            () => FakeOperationRunner(
              runningState(
                const OperationProgress(
                  kind: OperationKind.bulk,
                  label: 'bulk.download',
                  done: 1,
                  total: 5,
                ),
              ),
            ),
          ),
        ],
      );
      await pumpLibraryPage(tester, container);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Bulk actions (5)'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('download', () {
    testWidgets('confirms with the count, runs, summarises', (tester) async {
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Download');

      expect(find.text('Download missing assets?'), findsOneWidget);
      expect(
        find.text('The missing asset files of 5 mods will be downloaded.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Download'));
      await tester.pumpAndSettle();

      expect(service.downloadCalls, hasLength(1));
      expect(paths(service.downloadCalls.single), paths(library.mods));
      expect(find.text('Downloaded 5 files for 5 mods'), findsOneWidget);
      expect(find.byType(BulkFailuresDialog), findsNothing);
    });

    testWidgets('Cancel in the confirmation does nothing', (tester) async {
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Download');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.downloadCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('failures open the results dialog with the failed mods', (
      tester,
    ) async {
      service.downloadResult = BulkDownloadResult(
        outcomes: [
          BulkModOutcome(
            mod: library.alpha,
            value: FakeBulkService.downloadedOne(library.alpha),
          ),
          BulkModOutcome(
            mod: library.beta,
            value: DownloadBatchResult(const [
              DownloadOutcome(
                url: 'https://example.com/a.png',
                type: AssetType.image,
                status: DownloadStatus.failed,
                httpStatus: 404,
              ),
            ]),
          ),
          BulkModOutcome(mod: library.gamma, error: 'disk full'),
        ],
        cancelled: true,
      );
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Download');
      await tester.tap(find.widgetWithText(FilledButton, 'Download'));
      await tester.pumpAndSettle();

      expect(find.byType(BulkFailuresDialog), findsOneWidget);
      expect(
        find.text(
          'Downloaded 1 file for 5 mods, 1 files failed (cancelled after 3/5)',
        ),
        findsOneWidget,
      );
      final dialog = find.byType(BulkFailuresDialog);
      Finder inDialog(String text) =>
          find.descendant(of: dialog, matching: find.text(text));
      expect(inDialog('2 mods failed'), findsOneWidget);
      expect(inDialog('Beta Mod'), findsOneWidget);
      expect(inDialog('1 file failed'), findsOneWidget);
      expect(inDialog('Gamma Mod'), findsOneWidget);
      expect(inDialog('disk full'), findsOneWidget);
    });
  });

  group('backup', () {
    testWidgets('dialog choices reach the service', (tester) async {
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Backup');

      expect(find.byType(BulkBackupDialog), findsOneWidget);
      expect(find.text('5 mods will be backed up.'), findsOneWidget);
      expect(find.text(fixtureDirectories.backupsDir), findsOneWidget);
      // The default folder is the configured one, so no "use as default".
      expect(
        find.text('Use this folder as the default backups folder'),
        findsNothing,
      );
      await tester.tap(find.text('Skip'));
      await tester.tap(find.text('Delete all asset files, shared ones too'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(service.backupCalls, hasLength(1));
      final call = service.backupCalls.single;
      expect(paths(call.mods), paths(library.mods));
      expect(call.folder, fixtureDirectories.backupsDir);
      expect(call.behavior, BulkBackupBehavior.skip);
      expect(call.deletion, PostBackupDeletion.deleteAllAssets);
      expect(call.setAsDefault, isFalse);
      expect(find.text('Backed up 5 mods'), findsOneWidget);
    });

    testWidgets('a picked folder can become the default', (tester) async {
      final other = p.join(fixtureRoot, 'Elsewhere');
      directoryPicker.results.add(other);
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Backup');
      await tester.tap(find.text('Select folder'));
      await tester.pumpAndSettle();

      expect(find.text(p.normalize(other)), findsOneWidget);
      await tester.tap(
        find.text('Use this folder as the default backups folder'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      final call = service.backupCalls.single;
      expect(call.folder, p.normalize(other));
      expect(call.setAsDefault, isTrue);
      expect(call.behavior, BulkBackupBehavior.replaceIfOutOfDate);
      expect(call.deletion, PostBackupDeletion.none);
    });

    testWidgets('Confirm is disabled without a folder', (tester) async {
      container = ProviderContainer.test(
        overrides: [
          ...libraryPageOverrides(
            library: () => SpyLibraryController(library.state),
            directories: fixtureDirectories.copyWith(backupsDir: ''),
          ),
          fakeBulkServiceOverride(),
          directoryPickerProvider.overrideWithValue(directoryPicker),
        ],
      );
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Backup');

      expect(find.text('No folder selected'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm'),
      );
      expect(confirm.onPressed, isNull);
    });

    testWidgets('Download & backup uses the same dialog', (tester) async {
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Download & backup');

      expect(find.byType(BulkBackupDialog), findsOneWidget);
      expect(
        find.text(
          'The missing asset files of 5 mods will be downloaded, then each '
          'one is backed up.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(service.backupCalls, isEmpty);
      final call = service.downloadAndBackupCalls.single;
      expect(call.mods, hasLength(5));
      expect(call.behavior, BulkBackupBehavior.replace);
      expect(find.text('Downloaded 5 files, backed up 5 mods'), findsOneWidget);
    });
  });

  group('delete assets', () {
    testWidgets('scope radio reaches the service', (tester) async {
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Delete assets');

      expect(find.byType(BulkDeleteAssetsDialog), findsOneWidget);
      expect(
        find.text('The cached asset files of 5 mods will be deleted.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete shared files too'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      final (mods, scope) = service.deleteCalls.single;
      expect(mods, hasLength(5));
      expect(scope, DeleteAssetsScope.all);
      expect(find.text('Deleted 5 files'), findsOneWidget);
    });

    testWidgets('defaults to exclusive files only', (tester) async {
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Delete assets');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(service.deleteCalls.single.$2, DeleteAssetsScope.exclusiveOnly);
    });
  });

  group('check URLs', () {
    testWidgets('confirms, runs and shows the bulk results dialog', (
      tester,
    ) async {
      service.checkUrlsResult = BulkUrlCheckResult(
        outcomes: [
          BulkModOutcome(
            mod: library.alpha,
            value: const UrlCheckResult(
              invalidUrls: [],
              cancelled: false,
              checked: 4,
              total: 4,
            ),
          ),
          BulkModOutcome(
            mod: library.beta,
            value: const UrlCheckResult(
              invalidUrls: ['https://dead.example/1', 'https://dead.example/2'],
              cancelled: false,
              checked: 5,
              total: 5,
            ),
          ),
        ],
        cancelled: false,
      );
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Check for invalid URLs');

      expect(find.text('Check URLs?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Check URLs'));
      await tester.pumpAndSettle();

      expect(service.checkUrlsCalls.single, hasLength(5));
      expect(find.byType(BulkUrlCheckResultsDialog), findsOneWidget);
      expect(find.text('URL check complete'), findsOneWidget);
      expect(find.text('Beta Mod (2)'), findsOneWidget);
      expect(find.text('https://dead.example/1'), findsNothing);
      await tester.tap(find.text('Beta Mod (2)'));
      await tester.pumpAndSettle();
      expect(find.text('https://dead.example/1'), findsOneWidget);
      expect(find.text('Copy all invalid URLs'), findsOneWidget);
    });
  });

  group('Workshop update', () {
    testWidgets('asks with Force update, calls the bulk service', (
      tester,
    ) async {
      await pumpLibraryPage(tester, container);
      await pickItem(tester, 'Update from Steam Workshop');

      expect(find.text('Update from Steam Workshop?'), findsOneWidget);
      await tester.tap(find.text('Force update'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();

      final (mods, force) = service.updateWorkshopCalls.single;
      expect(mods, hasLength(5));
      expect(force, isTrue);
      expect(find.byType(WorkshopUpdateResultsDialog), findsOneWidget);
      expect(find.text('Updated (5)'), findsOneWidget);
    });
  });

  testWidgets('Import backups opens the .ttsmod picker', (tester) async {
    await pumpLibraryPage(tester, container);
    await pickItem(tester, 'Import backups');
    expect(filePicker.ttsmodInitialDirectories, [
      fixtureDirectories.backupsDir,
    ]);
  });

  group('multi-select view', () {
    testWidgets('buttons run the bulk flows on the selected mods', (
      tester,
    ) async {
      container.read(selectionProvider.notifier).selectMany([
        library.beta.jsonPath,
        library.delta.jsonPath,
      ]);
      await pumpLibraryPage(tester, container);
      expect(find.byType(MultiSelectView), findsOneWidget);
      expect(find.text('Update mods'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Download'));
      await tester.pumpAndSettle();
      expect(
        find.text('The missing asset files of 2 mods will be downloaded.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Download').last);
      await tester.pumpAndSettle();

      expect(
        paths(service.downloadCalls.single),
        paths([library.beta, library.delta]),
      );
      expect(find.text('Downloaded 2 files for 2 mods'), findsOneWidget);
    });

    testWidgets('Delete assets button opens the bulk dialog', (tester) async {
      container.read(selectionProvider.notifier).selectMany([
        library.alpha.jsonPath,
        library.gamma.jsonPath,
      ]);
      await pumpLibraryPage(tester, container);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete assets'));
      await tester.pumpAndSettle();
      expect(find.byType(BulkDeleteAssetsDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(
        paths(service.deleteCalls.single.$1),
        paths([library.alpha, library.gamma]),
      );
    });
  });
}
