// The bottom bar "Backup" button: folder resolution (no backups folder,
// existing archive, another folder), the runner hand-off and the result
// snack bars; the progress bar while a backup runs.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_actions.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_progress_bar.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';

import '../../asset_detail/presentation/asset_detail_test_harness.dart';
import '../../library/presentation/presentation_test_harness.dart'
    show fixtureDirectories, fixtureRoot;
import '../../operations/presentation/fake_operation_runner.dart';
import '../../startup/startup_test_helpers.dart' show FakeDirectoryPicker;
import 'fake_backup_service.dart';

void main() {
  late AssetDetailHarness h;
  late FakeBackupService service;
  late FakeDirectoryPicker picker;

  /// A second folder the user "picks".
  final String pickedDir = p.join(fixtureRoot, 'Elsewhere');

  Future<void> setUpHarness({
    List<String?> pickerResults = const [],
    List<Override> extra = const [],
  }) async {
    picker = FakeDirectoryPicker([...pickerResults]);
    h = await AssetDetailHarness.create(
      overrides: [
        fakeBackupServiceOverride(),
        directoryPickerProvider.overrideWithValue(picker),
        ...extra,
      ],
    );
    service = h.container.read(backupServiceProvider) as FakeBackupService;
  }

  Finder button(String label) => find.widgetWithText(FilledButton, label);

  Future<void> tapBackup(WidgetTester tester) async {
    h.select(h.fixture.alpha);
    await pumpPanel(tester, h);
    await tester.tap(button('Backup'));
    await tester.pumpAndSettle();
  }

  Backup existingAt(String dir) {
    final name = FakeBackupService.fileNameFor(h.fixture.alpha);
    return Backup(
      path: p.normalize(p.join(dir, name)),
      fileName: name,
      folder: p.basename(dir),
      modified: DateTime(2024),
      sizeBytes: 10,
      assetCount: 1,
    );
  }

  group('with a backups folder', () {
    setUp(setUpHarness);

    testWidgets('a mod without a backup is backed up straight away', (
      tester,
    ) async {
      await tapBackup(tester);

      expect(service.createCalls, hasLength(1));
      final (mod, dir) = service.createCalls.single;
      expect(mod.jsonPath, h.fixture.alpha.jsonPath);
      expect(dir, fixtureDirectories.backupsDir);
      expect(picker.titles, isEmpty);
      expect(find.text('Backup created: Alpha Mod.ttsmod'), findsOneWidget);
      // The default folder is untouched.
      expect(
        h.container.read(directoriesProvider).value!.backupsDir,
        fixtureDirectories.backupsDir,
      );
    });

    testWidgets('a refused start shows the already-running snack bar', (
      tester,
    ) async {
      service.alreadyRunning = true;
      await tapBackup(tester);

      expect(find.text('An operation is already running'), findsOneWidget);
    });

    testWidgets('an error while writing is reported', (tester) async {
      service.createError = Exception('disk full');
      await tapBackup(tester);

      expect(find.textContaining('Backup failed:'), findsOneWidget);
      expect(find.textContaining('disk full'), findsOneWidget);
    });
  });

  group('without a backups folder', () {
    testWidgets('asks for a folder, then whether to make it the default', (
      tester,
    ) async {
      await setUpHarness(pickerResults: [pickedDir]);
      service.backupsDir = '';
      await tapBackup(tester);

      expect(picker.titles, ['Select a backups folder']);
      expect(find.text('Back up to this folder?'), findsOneWidget);
      expect(find.textContaining(pickedDir), findsOneWidget);
      expect(
        find.text('Use this folder as the default backups folder'),
        findsOneWidget,
      );
      // Confirm without the checkbox: the backup is written, no default.
      await tester.tap(find.widgetWithText(FilledButton, 'Backup').last);
      await tester.pumpAndSettle();

      expect(service.createCalls.single.$2, p.normalize(pickedDir));
      // The stored folders are untouched.
      expect(
        h.container.read(directoriesProvider).value!.backupsDir,
        fixtureDirectories.backupsDir,
      );
      expect(find.text('Backup created: Alpha Mod.ttsmod'), findsOneWidget);
    });

    testWidgets('the checkbox makes the picked folder the default', (
      tester,
    ) async {
      await setUpHarness(pickerResults: [pickedDir]);
      service.backupsDir = '';
      await tapBackup(tester);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Backup').last);
      await tester.pumpAndSettle();

      expect(service.createCalls.single.$2, p.normalize(pickedDir));
      expect(
        h.container.read(directoriesProvider).value!.backupsDir,
        p.normalize(pickedDir),
      );
    });

    testWidgets('cancelling the picker or the confirmation does nothing', (
      tester,
    ) async {
      await setUpHarness(pickerResults: [null, pickedDir]);
      service.backupsDir = '';
      await tapBackup(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.createCalls, isEmpty);

      await tester.tap(button('Backup'));
      await tester.pumpAndSettle();
      expect(find.text('Back up to this folder?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.createCalls, isEmpty);
    });
  });

  group('when the archive already exists', () {
    testWidgets('Replace overwrites it in place', (tester) async {
      await setUpHarness();
      service.existing = [existingAt(fixtureDirectories.backupsDir)];
      await tapBackup(tester);

      expect(find.text('Backup already exists'), findsOneWidget);
      expect(find.textContaining('Alpha Mod.ttsmod'), findsOneWidget);
      expect(find.text('Select new folder'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(service.createCalls.single.$2, fixtureDirectories.backupsDir);
      expect(find.text('Backup created: Alpha Mod.ttsmod'), findsOneWidget);
    });

    testWidgets('Select new folder writes to the picked folder', (
      tester,
    ) async {
      await setUpHarness(pickerResults: [pickedDir]);
      service.existing = [existingAt(fixtureDirectories.backupsDir)];
      await tapBackup(tester);

      await tester.tap(find.text('Select new folder'));
      await tester.pumpAndSettle();

      expect(picker.initialDirectories, [fixtureDirectories.backupsDir]);
      // No second prompt: the new folder has no archive.
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.createCalls.single.$2, p.normalize(pickedDir));
      expect(service.targetCalls.last.$2, p.normalize(pickedDir));
    });

    testWidgets('an archive in the new folder asks again', (tester) async {
      await setUpHarness(pickerResults: [pickedDir]);
      service.existing = [
        existingAt(fixtureDirectories.backupsDir),
        existingAt(pickedDir),
      ];
      await tapBackup(tester);

      await tester.tap(find.text('Select new folder'));
      await tester.pumpAndSettle();
      expect(find.text('Backup already exists'), findsOneWidget);
      expect(find.textContaining(p.normalize(pickedDir)), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(service.createCalls.single.$2, p.normalize(pickedDir));
    });

    testWidgets('Cancel writes nothing', (tester) async {
      await setUpHarness();
      service.existing = [existingAt(fixtureDirectories.backupsDir)];
      await tapBackup(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(service.createCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('while a backup runs', () {
    testWidgets('the bottom bar shows the progress bar with the label', (
      tester,
    ) async {
      await setUpHarness(
        extra: [
          operationRunnerProvider.overrideWith(
            () => FakeOperationRunner(
              runningState(
                const OperationProgress(
                  kind: OperationKind.backup,
                  label: 'backup.writing',
                  done: 3,
                  total: 10,
                  detail: 'img1.png',
                ),
              ),
            ),
          ),
        ],
      );
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      expect(find.byType(SelectedModActions), findsNothing);
      expect(find.byType(OperationProgressBar), findsOneWidget);
      expect(find.text('Writing backup 3/10'), findsOneWidget);
      expect(find.text('img1.png'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    });
  });
}
