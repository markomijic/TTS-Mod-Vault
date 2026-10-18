import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/dialogs/delete_mod_dialog.dart';

import 'dialog_test_harness.dart';

void main() {
  late DialogFixture fixture;
  late String alphaPath;
  late String alphaImage;

  setUp(() {
    fixture = DialogFixture.create();
    alphaPath = fixture.library.writeJson(
      'Mods/Workshop/111.json',
      saveName: 'Alpha',
    );
    alphaImage = fixture.library.writeSiblingImage(alphaPath);
  });

  Future<Mod> open(WidgetTester tester) async {
    final mod = await fixture.indexed(tester, alphaPath);
    await pumpAndOpenDialog(
      tester,
      fixture,
      open: (context, ref) => showDeleteModDialog(context, ref, mod),
    );
    return mod;
  }

  testWidgets('shows the name and file name with a destructive Delete', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Delete mod?'), findsOneWidget);
    expect(find.textContaining('delete\nAlpha?'), findsOneWidget);
    expect(find.textContaining('111.json'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    final scheme = Theme.of(tester.element(find.byType(AlertDialog)))
        .colorScheme;
    expect(button.style?.backgroundColor?.resolve({}), scheme.error);
  });

  testWidgets('Cancel keeps the files', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(File(alphaPath).existsSync(), isTrue);
    expect(fixture.current(alphaPath), isNotNull);
  });

  testWidgets('Delete removes the JSON and image and reports success', (
    tester,
  ) async {
    await open(tester);
    await runUntil(
      tester,
      () => tester.tap(find.widgetWithText(FilledButton, 'Delete')),
      () => find.text('Alpha deleted').evaluate().isNotEmpty,
    );

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Alpha deleted'), findsOneWidget);
    expect(File(alphaPath).existsSync(), isFalse);
    expect(File(alphaImage).existsSync(), isFalse);
    expect(fixture.current(alphaPath), isNull);
  });
}
