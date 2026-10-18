import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/dialogs/rename_mod_dialog.dart';

import 'dialog_test_harness.dart';

void main() {
  late DialogFixture fixture;
  late String alphaPath;
  late String alphaBackup;
  late String deltaPath;
  late String tokenPath;

  setUp(() {
    fixture = DialogFixture.create();
    final lib = fixture.library;
    alphaPath = lib.writeJson('Mods/Workshop/111.json', saveName: 'Alpha');
    alphaBackup = lib.writeBackup('Alpha (111).ttsmod');
    deltaPath = lib.writeJson('Mods/Workshop/444.json', saveName: 'Delta');
    // A saved object without a SaveName: the service refuses to rename it.
    // Saved objects are not indexed by default, so the Mod is built by hand.
    tokenPath = p.normalize(p.join(lib.savedObjectsDir, 'Token.json'));
    File(tokenPath).writeAsStringSync('{"ObjectStates": []}');
  });

  Mod tokenMod() => Mod(
    ref: ModRef.fromPath(ModType.savedObject, tokenPath),
    saveName: '',
    folder: 'Saved Objects',
    epochTime: null,
    modified: DateTime(2024),
    sizeBytes: 20,
    imagePath: null,
    audio: AudioVisibility.useGlobalSetting,
    summary: const AssetSummary(
      total: 0,
      present: 0,
      hasAudio: false,
      totalByType: {},
      presentByType: {},
    ),
  );

  Future<Mod> open(WidgetTester tester, String jsonPath) async {
    final mod = jsonPath == tokenPath
        ? tokenMod()
        : await fixture.indexed(tester, jsonPath);
    await pumpAndOpenDialog(
      tester,
      fixture,
      open: (context, ref) => showRenameModDialog(context, mod),
    );
    return mod;
  }

  Future<void> rename(
    WidgetTester tester,
    String name, {
    bool Function() done = noDialog,
  }) async {
    await tester.enterText(fieldLabelled('Name'), name);
    await tester.pump();
    await runUntil(
      tester,
      () => tester.tap(find.widgetWithText(FilledButton, 'Rename')),
      done,
    );
  }

  testWidgets('prefills the name and disables Rename until it changes', (
    tester,
  ) async {
    final mod = await open(tester, alphaPath);
    expect(mod.backup, isNotNull, reason: 'fixture backup must match');

    expect(find.text('Rename mod'), findsOneWidget);
    expect(fieldText(tester, 'Name'), 'Alpha');
    expect(buttonEnabled(tester, 'Rename'), isFalse);
    expect(find.text('Also rename the backup file'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );

    await tester.enterText(fieldLabelled('Name'), '  Alpha  ');
    await tester.pump();
    expect(buttonEnabled(tester, 'Rename'), isFalse);

    await tester.enterText(fieldLabelled('Name'), 'Alpha 2');
    await tester.pump();
    expect(buttonEnabled(tester, 'Rename'), isTrue);
  });

  testWidgets('an empty name shows the validation message; no backup, no '
      'checkbox', (tester) async {
    await open(tester, deltaPath);
    expect(find.text('Also rename the backup file'), findsNothing);

    await tester.enterText(fieldLabelled('Name'), '   ');
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(buttonEnabled(tester, 'Rename'), isFalse);
  });

  testWidgets('Rename rewrites the SaveName, renames the backup by default '
      'and closes with a snack bar', (tester) async {
    await open(tester, alphaPath);
    await rename(tester, '  New Name ');

    expect(find.byType(RenameModDialog), findsNothing);
    expect(find.text('Renamed to "New Name"'), findsOneWidget);
    expect(File(alphaPath).readAsStringSync(), contains('"New Name"'));
    expect(fixture.current(alphaPath)?.saveName, 'New Name');
    expect(File(alphaBackup).existsSync(), isFalse);
    expect(
      File(p.join(fixture.library.backupsDir, 'New Name (111).ttsmod'))
          .existsSync(),
      isTrue,
    );
  });

  testWidgets('unchecking the box keeps the backup file as it is', (
    tester,
  ) async {
    await open(tester, alphaPath);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await rename(tester, 'Other');

    expect(fixture.current(alphaPath)?.saveName, 'Other');
    expect(File(alphaBackup).existsSync(), isTrue);
  });

  testWidgets('submitting from the keyboard renames too', (tester) async {
    await open(tester, deltaPath);
    await tester.enterText(fieldLabelled('Name'), 'Keyboard');
    await tester.pump();
    await runUntil(
      tester,
      () => tester.testTextInput.receiveAction(TextInputAction.done),
      noDialog,
    );

    expect(find.byType(RenameModDialog), findsNothing);
    expect(fixture.current(deltaPath)?.saveName, 'Keyboard');
  });

  testWidgets('a failure on a saved object keeps the dialog open and '
      'explains the SaveName rule', (tester) async {
    await open(tester, tokenPath);
    expect(find.text('Rename saved object'), findsOneWidget);
    expect(fieldText(tester, 'Name'), 'Token');

    await rename(
      tester,
      'Coin',
      done: () => find.textContaining('no SaveName').evaluate().isNotEmpty,
    );

    expect(find.byType(RenameModDialog), findsOneWidget);
    expect(find.textContaining('Only mods and saves carry'), findsOneWidget);
    // The service's message is in the snack bar.
    expect(find.textContaining('no SaveName'), findsOneWidget);
    expect(buttonEnabled(tester, 'Rename'), isTrue);
    expect(File(tokenPath).readAsStringSync(), '{"ObjectStates": []}');
  });

  testWidgets('Cancel closes without changing anything', (tester) async {
    await open(tester, alphaPath);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(RenameModDialog), findsNothing);
    expect(fixture.current(alphaPath)?.saveName, 'Alpha');
  });
}
