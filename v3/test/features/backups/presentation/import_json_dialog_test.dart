// The Import JSON dialog: validation, type selector and folder override,
// the optional image, and the `importJson` call.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart';
import 'package:tts_mod_vault/features/backups/presentation/file_picker_service.dart';
import 'package:tts_mod_vault/features/backups/presentation/import_json_dialog.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';

import '../../library/presentation/presentation_test_harness.dart';
import '../../startup/startup_test_helpers.dart' show FakeDirectoryPicker;
import 'fake_backup_service.dart';
import 'fake_file_picker_service.dart';
import 'shell_test_harness.dart';

void main() {
  late FixtureLibrary library;
  late FakeFilePickerService filePicker;
  late FakeDirectoryPicker folderPicker;
  late ProviderContainer container;
  late FakeBackupService service;

  final String jsonFile = p.join(fixtureRoot, 'Downloads', '42.json');
  final String pngFile = p.join(fixtureRoot, 'Downloads', 'cover.png');
  final String otherFolder = p.join(fixtureRoot, 'Other');

  setUpAll(() => library = FixtureLibrary.create());
  tearDownAll(() => library.delete());

  setUp(() {
    filePicker = FakeFilePickerService();
    folderPicker = FakeDirectoryPicker([otherFolder]);
    container = shellContainer(
      library.state,
      overrides: [
        fakeBackupServiceOverride(),
        filePickerServiceProvider.overrideWithValue(filePicker),
        directoryPickerProvider.overrideWithValue(folderPicker),
      ],
    );
    service = container.read(backupServiceProvider) as FakeBackupService;
  });

  Future<void> openDialog(WidgetTester tester) async {
    await pumpShell(tester, container);
    await tapSidebar(tester, 'Import JSON');
    expect(find.byType(ImportJsonDialog), findsOneWidget);
  }

  Finder importButton() => find.widgetWithText(FilledButton, 'Import');

  bool importEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(importButton()).enabled;

  Finder segment(String label) => find.descendant(
    of: find.byType(SegmentedButton<ModType>),
    matching: find.text(label),
  );

  testWidgets('opens with the Workshop folder and Import disabled', (
    tester,
  ) async {
    await openDialog(tester);

    expect(find.text('Import JSON'), findsOneWidget);
    expect(find.text('No file selected'), findsNWidgets(2));
    expect(
      find.text('Import to: ${fixtureDirectories.workshopDir}'),
      findsOneWidget,
    );
    expect(importEnabled(tester), isFalse);
    for (final label in ['Mods', 'Saves', 'Saved Objects']) {
      expect(segment(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the type selector switches the destination folder', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.tap(segment('Saves'));
    await tester.pumpAndSettle();
    expect(
      find.text('Import to: ${fixtureDirectories.savesDir}'),
      findsOneWidget,
    );

    await tester.tap(segment('Saved Objects'));
    await tester.pumpAndSettle();
    expect(
      find.text('Import to: ${fixtureDirectories.savedObjectsDir}'),
      findsOneWidget,
    );
  });

  testWidgets('Select folder overrides the destination until the type '
      'changes', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Select folder'));
    await tester.pumpAndSettle();
    expect(folderPicker.initialDirectories, [fixtureDirectories.workshopDir]);
    expect(find.text('Import to: ${p.normalize(otherFolder)}'), findsOneWidget);

    await tester.tap(segment('Saves'));
    await tester.pumpAndSettle();
    expect(
      find.text('Import to: ${fixtureDirectories.savesDir}'),
      findsOneWidget,
    );
  });

  testWidgets('a picked JSON enables Import and the import runs', (
    tester,
  ) async {
    filePicker.jsonFile = jsonFile;
    await openDialog(tester);

    await tester.tap(find.text('Select JSON'));
    await tester.pumpAndSettle();

    expect(filePicker.jsonPicks, 1);
    expect(find.text('42.json'), findsOneWidget);
    expect(importEnabled(tester), isTrue);

    await tester.tap(importButton());
    await tester.pumpAndSettle();

    expect(find.byType(ImportJsonDialog), findsNothing);
    final call = service.importJsonCalls.single;
    expect(call.json, p.normalize(jsonFile));
    expect(call.folder, fixtureDirectories.workshopDir);
    expect(call.type, ModType.mod);
    expect(call.png, isNull);
    expect(find.text('Imported 42.json'), findsOneWidget);
  });

  testWidgets('the optional image is renamed after the JSON and can be '
      'cleared', (tester) async {
    filePicker
      ..jsonFile = jsonFile
      ..pngFile = pngFile;
    await openDialog(tester);

    await tester.tap(find.text('Select image'));
    await tester.pumpAndSettle();
    expect(find.text('cover.png'), findsOneWidget);
    // Without a JSON the "saved as" note is not shown yet.
    expect(find.textContaining('will be saved as'), findsNothing);

    await tester.tap(find.text('Select JSON'));
    await tester.pumpAndSettle();
    expect(find.text('The image will be saved as 42.png'), findsOneWidget);

    await tester.tap(segment('Saved Objects'));
    await tester.pumpAndSettle();
    await tester.tap(importButton());
    await tester.pumpAndSettle();

    final call = service.importJsonCalls.single;
    expect(call.png, p.normalize(pngFile));
    expect(call.type, ModType.savedObject);
    expect(call.folder, fixtureDirectories.savedObjectsDir);
  });

  testWidgets('Clear image drops the picked image', (tester) async {
    filePicker
      ..jsonFile = jsonFile
      ..pngFile = pngFile;
    await openDialog(tester);

    await tester.tap(find.text('Select image'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear image'));
    await tester.pumpAndSettle();

    expect(find.text('cover.png'), findsNothing);
    expect(find.text('No file selected'), findsNWidgets(2));
    expect(find.byTooltip('Clear image'), findsNothing);
  });

  testWidgets('a cancelled JSON picker leaves Import disabled', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Select JSON'));
    await tester.pumpAndSettle();

    expect(filePicker.jsonPicks, 1);
    expect(importEnabled(tester), isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportJsonDialog), findsNothing);
    expect(service.importJsonCalls, isEmpty);
  });

  testWidgets('a refused start shows the already-running snack bar', (
    tester,
  ) async {
    filePicker.jsonFile = jsonFile;
    service.alreadyRunning = true;
    await openDialog(tester);

    await tester.tap(find.text('Select JSON'));
    await tester.pumpAndSettle();
    await tester.tap(importButton());
    await tester.pumpAndSettle();

    expect(find.text('An operation is already running'), findsOneWidget);
  });
}
