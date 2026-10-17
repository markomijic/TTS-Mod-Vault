import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/images_viewer/presentation/images_viewer_page.dart';
import 'package:tts_mod_vault/features/library/presentation/dialogs/rename_mod_dialog.dart';
import 'package:tts_mod_vault/features/library/presentation/dialogs/save_as_mod_dialog.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_grid_card.dart';

import '../presentation_test_harness.dart';
import 'dialog_test_harness.dart' show fieldText;

/// The menu entries open their dialogs and pages; the dialogs' own
/// behaviour is covered by the per-dialog tests.
void main() {
  late FixtureLibrary library;
  late ProviderContainer container;

  setUpAll(() => library = FixtureLibrary.create());
  tearDownAll(() => library.delete());

  setUp(() {
    container = ProviderContainer.test(
      overrides: [
        ...libraryPageOverrides(
          library: () => SpyLibraryController(library.state),
        ),
      ],
    );
  });

  Finder card(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ModsGridCard));

  Future<void> openMenu(WidgetTester tester, Finder target) async {
    await tester.tap(target, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  testWidgets('Rename opens the rename dialog for the clicked mod', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    await openMenu(tester, card('Beta Mod'));
    await tester.tap(find.text('Rename mod'));
    await tester.pumpAndSettle();

    expect(find.byType(RenameModDialog), findsOneWidget);
    expect(fieldText(tester, 'Name'), 'Beta Mod');
    // Beta has a backup, so the checkbox is offered.
    expect(find.text('Also rename the backup file'), findsOneWidget);
  });

  testWidgets('Delete opens the confirmation for the clicked mod', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    await openMenu(tester, card('Delta Mod'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete mod?'), findsOneWidget);
    expect(find.textContaining('Delta Mod'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Save as Mod opens the save-as dialog for a save', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    await tester.tap(find.text('Saves'));
    await tester.pumpAndSettle();
    await openMenu(tester, find.byType(ModsGridCard));
    await tester.tap(find.text('Save as Mod'));
    await tester.pumpAndSettle();

    expect(find.byType(SaveAsModDialog), findsOneWidget);
    expect(fieldText(tester, 'File name'), 'My Save');
  });

  testWidgets('View images pushes the images viewer', (tester) async {
    await pumpLibraryPage(tester, container);
    await openMenu(tester, card('Beta Mod'));
    await tester.tap(find.text('View images'));
    await tester.pumpAndSettle();

    expect(find.byType(ImagesViewerPage), findsOneWidget);
    expect(find.text('Beta Mod – 0 images'), findsOneWidget);
    expect(find.text('No downloaded images'), findsOneWidget);
  });

  testWidgets('Download is still stubbed', (tester) async {
    await pumpLibraryPage(tester, container);
    await openMenu(tester, card('Beta Mod'));
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Download: not implemented yet'), findsOneWidget);
  });
}
