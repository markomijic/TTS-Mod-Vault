// "Update from Steam Workshop" in the mod context menu: confirmation with
// the Force update checkbox, the service call and the results dialog.

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_grid_card.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart';
import 'package:tts_mod_vault/features/workshop/presentation/workshop_results_dialog.dart';

import '../../library/presentation/presentation_test_harness.dart';
import 'fake_workshop_service.dart';

void main() {
  late FixtureLibrary library;
  late ProviderContainer container;
  late FakeWorkshopService service;

  setUpAll(() => library = FixtureLibrary.create());
  tearDownAll(() => library.delete());

  setUp(() {
    container = ProviderContainer.test(
      overrides: [
        ...libraryPageOverrides(
          library: () => SpyLibraryController(library.state),
        ),
        fakeWorkshopServiceOverride(),
      ],
    );
    service = container.read(workshopServiceProvider) as FakeWorkshopService;
  });

  Finder card(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ModsGridCard));

  Future<void> openUpdate(WidgetTester tester) async {
    await tester.tap(card('Beta Mod'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update from Steam Workshop'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks first; Cancel does nothing', (tester) async {
    await pumpLibraryPage(tester, container);
    await openUpdate(tester);

    expect(find.text('Update from Steam Workshop?'), findsOneWidget);
    expect(
      find.textContaining('"Beta Mod" will be downloaded again'),
      findsOneWidget,
    );
    expect(find.text('Force update'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.updateModsCalls, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Update passes the mod and the Force flag, then shows results', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    await openUpdate(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pumpAndSettle();

    expect(service.updateModsCalls, hasLength(1));
    var (mods, force) = service.updateModsCalls.single;
    expect(mods.map((m) => m.jsonPath), [library.beta.jsonPath]);
    expect(force, isFalse);
    expect(find.byType(WorkshopUpdateResultsDialog), findsOneWidget);
    expect(find.text('Update complete'), findsOneWidget);
    expect(find.text('Updated (1)'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await openUpdate(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pumpAndSettle();

    expect(service.updateModsCalls, hasLength(2));
    (mods, force) = service.updateModsCalls.last;
    expect(force, isTrue);
  });
}
