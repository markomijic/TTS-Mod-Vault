import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';

import 'startup_test_helpers.dart';

void main() {
  late FixedStartupController controller;

  Future<FakeDirectoryPicker> pumpView(
    WidgetTester tester, {
    required Set<String> existing,
    List<String?> picks = const [],
    StartupDirectoriesError? error,
  }) async {
    final picker = FakeDirectoryPicker(List.of(picks));
    controller = FixedStartupController([
      StartupNeedsDirectories(
        modsDirExists: existing.contains(testDefaults.modsDir),
        savesDirExists: existing.contains(testDefaults.savesDir),
        error: error,
      ),
    ]);
    await pumpStartupApp(
      tester,
      overrides: [
        ...startupOverrides(existing: existing),
        directoryPickerProvider.overrideWithValue(picker),
        startupControllerProvider.overrideWith(() => controller),
      ],
    );
    return picker;
  }

  Finder continueButton() => find.widgetWithText(FilledButton, 'Continue');

  bool continueEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(continueButton()).enabled;

  Finder fieldLabelled(String label) => find.widgetWithText(TextField, label);

  testWidgets('shows the default paths with not-found status and a disabled '
      'Continue', (tester) async {
    await pumpView(tester, existing: const {});

    expect(
      tester.widget<TextField>(fieldLabelled('Mods folder')).controller?.text,
      testDefaults.modsDir,
    );
    expect(
      tester.widget<TextField>(fieldLabelled('Saves folder')).controller?.text,
      testDefaults.savesDir,
    );
    expect(find.text('Folder not found'), findsNWidgets(2));
    expect(find.text('Not set'), findsOneWidget);
    expect(continueEnabled(tester), isFalse);
  });

  testWidgets('an existing default shows as found', (tester) async {
    await pumpView(tester, existing: {testDefaults.modsDir});

    expect(find.text('Found: ${testDefaults.modsDir}'), findsOneWidget);
    expect(find.text('Folder not found'), findsOneWidget);
    expect(continueEnabled(tester), isFalse);
  });

  testWidgets('typing valid paths enables Continue, which hands the raw '
      'paths to the controller', (tester) async {
    await pumpView(tester, existing: {pickedTts, pickedMods, pickedSaves});

    await tester.enterText(fieldLabelled('Mods folder'), pickedTts);
    await tester.pump();
    expect(find.text('Found: $pickedMods'), findsOneWidget);
    expect(continueEnabled(tester), isFalse);

    await tester.enterText(fieldLabelled('Saves folder'), pickedTts);
    await tester.pump();
    expect(find.text('Found: $pickedSaves'), findsOneWidget);
    expect(continueEnabled(tester), isTrue);

    await tester.tap(continueButton());
    await tester.pump();

    expect(controller.continued, [
      Directories(modsDir: pickedTts, savesDir: pickedTts),
    ]);
  });

  testWidgets('an existing folder that is not Mods shows the naming rule', (
    tester,
  ) async {
    await pumpView(tester, existing: {pickedTts, pickedSaves});

    await tester.enterText(fieldLabelled('Mods folder'), pickedTts);
    await tester.pump();

    expect(
      find.text('Folder must be named Mods or contain a Mods folder'),
      findsOneWidget,
    );
    expect(continueEnabled(tester), isFalse);
  });

  testWidgets('Browse fills the field from the picker', (tester) async {
    final picker = await pumpView(
      tester,
      existing: {pickedTts, pickedMods, pickedSaves},
      picks: [pickedMods],
    );

    final browse = find.widgetWithText(OutlinedButton, 'Browse');
    await tester.tap(browse.first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(fieldLabelled('Mods folder')).controller?.text,
      pickedMods,
    );
    expect(find.text('Found: $pickedMods'), findsOneWidget);
    expect(picker.titles, ['Mods folder']);
  });

  testWidgets('a cancelled picker leaves the field alone', (tester) async {
    await pumpView(tester, existing: const {}, picks: [null]);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Browse').first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(fieldLabelled('Mods folder')).controller?.text,
      testDefaults.modsDir,
    );
  });

  testWidgets('selecting the TTS folder fills both Mods and Saves', (
    tester,
  ) async {
    await pumpView(
      tester,
      existing: {pickedTts, pickedMods, pickedSaves},
      picks: [pickedTts],
    );

    await tester.tap(find.text('Select Tabletop Simulator folder'));
    await tester.pumpAndSettle();

    expect(find.text('Found: $pickedMods'), findsOneWidget);
    expect(find.text('Found: $pickedSaves'), findsOneWidget);
    expect(continueEnabled(tester), isTrue);
  });

  testWidgets('a non-existent backups folder blocks Continue; an existing one '
      'is passed along', (tester) async {
    await pumpView(
      tester,
      existing: {testDefaults.modsDir, testDefaults.savesDir, pickedBackups},
    );
    expect(continueEnabled(tester), isTrue);

    await tester.enterText(
      fieldLabelled('Backups folder (optional)'),
      '$pickedBackups-missing',
    );
    await tester.pump();
    expect(continueEnabled(tester), isFalse);
    expect(find.text('Folder not found'), findsOneWidget);

    await tester.enterText(
      fieldLabelled('Backups folder (optional)'),
      pickedBackups,
    );
    await tester.pump();
    expect(continueEnabled(tester), isTrue);

    await tester.tap(continueButton());
    await tester.pump();
    expect(controller.continued.single.backupsDir, pickedBackups);
  });

  testWidgets('a controller error is shown as a banner', (tester) async {
    await pumpView(
      tester,
      existing: const {},
      error: StartupDirectoriesError.invalidSavesDir,
    );

    expect(
      find.text('The selected Saves folder is not valid.'),
      findsOneWidget,
    );
  });

  testWidgets('a throwing picker shows a snack bar', (tester) async {
    await pumpStartupApp(
      tester,
      overrides: [
        ...startupOverrides(existing: const {}),
        directoryPickerProvider.overrideWithValue(_ThrowingPicker()),
        startupControllerProvider.overrideWith(
          () => FixedStartupController(const [
            StartupNeedsDirectories(
              modsDirExists: false,
              savesDirExists: false,
            ),
          ]),
        ),
      ],
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Browse').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Could not open the folder picker'), findsOneWidget);
  });
}

class _ThrowingPicker implements DirectoryPicker {
  @override
  Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async => throw StateError('no picker');
}
