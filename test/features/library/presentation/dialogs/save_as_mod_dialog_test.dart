import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/dialogs/save_as_mod_dialog.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';

import '../../../startup/startup_test_helpers.dart' show FakeDirectoryPicker;
import 'dialog_test_harness.dart';

void main() {
  late DialogFixture fixture;
  late String savePath;
  late String workshopDir;
  late FakeDirectoryPicker picker;

  setUp(() {
    picker = FakeDirectoryPicker([]);
    fixture = DialogFixture.create(
      overrides: [directoryPickerProvider.overrideWithValue(picker)],
    );
    workshopDir = p.normalize(fixture.library.workshopDir);
    savePath = fixture.library.writeJson(
      'Saves/TS_Save_12.json',
      saveName: 'My Save: "Final" <v2>',
    );
    fixture.library.writeSiblingImage(savePath);
  });

  Future<Mod> open(WidgetTester tester) async {
    final save = await fixture.indexed(tester, savePath);
    await pumpAndOpenDialog(
      tester,
      fixture,
      open: (context, ref) => showSaveAsModDialog(context, save),
    );
    return save;
  }

  group('sanitizeFileName', () {
    test('drops forbidden characters and trailing dots', () {
      expect(
        sanitizeFileName('My Save: "Final" <v2>...', fallback: 'x'),
        'My Save Final v2',
      );
      expect(sanitizeFileName('a/b\\c|d?e*f', fallback: 'x'), 'abcdef');
      expect(sanitizeFileName('  spaced   out  ', fallback: 'x'), 'spaced out');
    });

    test('falls back when nothing is left', () {
      expect(sanitizeFileName('???', fallback: 'TS_Save_12'), 'TS_Save_12');
      expect(sanitizeFileName('', fallback: 'id'), 'id');
    });
  });

  test('isValidFileName rejects empty and forbidden characters', () {
    expect(isValidFileName('ok name'), isTrue);
    expect(isValidFileName(''), isFalse);
    expect(isValidFileName('a:b'), isFalse);
    expect(isValidFileName('a/b'), isFalse);
  });

  testWidgets('defaults to the Workshop folder and a sanitised file name', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Save as Mod'), findsNWidgets(2)); // title + button
    expect(fieldText(tester, 'Target folder'), workshopDir);
    expect(fieldText(tester, 'File name'), 'My Save Final v2');
    expect(find.text('.json'), findsOneWidget);
    expect(buttonEnabled(tester, 'Save as Mod'), isTrue);
  });

  testWidgets('validates both fields', (tester) async {
    await open(tester);

    await tester.enterText(fieldLabelled('File name'), '');
    await tester.pump();
    expect(find.text('Enter a file name'), findsOneWidget);
    expect(buttonEnabled(tester, 'Save as Mod'), isFalse);

    await tester.enterText(fieldLabelled('File name'), 'bad:name');
    await tester.pump();
    expect(
      find.text('The file name contains characters that are not allowed'),
      findsOneWidget,
    );
    expect(buttonEnabled(tester, 'Save as Mod'), isFalse);

    await tester.enterText(fieldLabelled('File name'), 'good');
    await tester.enterText(fieldLabelled('Target folder'), ' ');
    await tester.pump();
    expect(find.text('Select a folder'), findsOneWidget);
    expect(buttonEnabled(tester, 'Save as Mod'), isFalse);
  });

  testWidgets('Browse fills the folder from the picker', (tester) async {
    final picked = p.join(workshopDir, 'Favourites');
    picker.results.addAll([picked, null]);
    await open(tester);

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'Target folder'), p.normalize(picked));
    expect(picker.initialDirectories, [workshopDir]);

    // Cancelling the picker keeps the current value.
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'Target folder'), p.normalize(picked));
  });

  testWidgets('Save as Mod copies the save into the folder under the typed '
      'name and reports it', (tester) async {
    await open(tester);
    final folder = p.join(workshopDir, 'Imported');

    await tester.enterText(fieldLabelled('Target folder'), '$folder ');
    await tester.enterText(fieldLabelled('File name'), ' Renamed Save ');
    await tester.pump();
    await runUntil(
      tester,
      () => tester.tap(find.widgetWithText(FilledButton, 'Save as Mod')),
      noDialog,
    );

    expect(find.byType(SaveAsModDialog), findsNothing);
    expect(find.text('My Save: "Final" <v2> saved as mod'), findsOneWidget);
    final copy = p.join(folder, 'Renamed Save.json');
    expect(File(copy).existsSync(), isTrue);
    expect(File(p.join(folder, 'Renamed Save.png')).existsSync(), isTrue);
    expect(File(savePath).existsSync(), isTrue, reason: 'original kept');
    expect(fixture.current(p.normalize(copy))?.ref.type, ModType.mod);
  });

  testWidgets('a failure message ends up in the snack bar', (tester) async {
    File(p.join(workshopDir, 'Taken.json')).writeAsStringSync('{}');
    await open(tester);

    await tester.enterText(fieldLabelled('File name'), 'Taken');
    await tester.pump();
    await runUntil(
      tester,
      () => tester.tap(find.widgetWithText(FilledButton, 'Save as Mod')),
      noDialog,
    );

    expect(find.byType(SaveAsModDialog), findsNothing);
    expect(find.textContaining('already exists'), findsOneWidget);
  });
}
