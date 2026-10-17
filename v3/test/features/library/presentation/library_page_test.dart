import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/features/backups/presentation/backups_view.dart';
import 'package:tts_mod_vault/features/backups/presentation/selected_backup_panel.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_view_options.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_grid_card.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_list_item.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_view.dart';
import 'package:tts_mod_vault/features/library/presentation/selected_mod_panel.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/library_search_field.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

import 'presentation_test_harness.dart';

void main() {
  late FixtureLibrary library;
  late SpyLibraryController controller;
  late InMemoryKeyValueStore store;
  late ProviderContainer container;

  setUpAll(() => library = FixtureLibrary.create());
  tearDownAll(() => library.delete());

  setUp(() {
    controller = SpyLibraryController(library.state);
    store = InMemoryKeyValueStore();
    container = ProviderContainer.test(
      overrides: libraryPageOverrides(library: () => controller, store: store),
    );
  });

  Finder card(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ModsGridCard));

  Finder segment(String label) => find.descendant(
    of: find.byType(SegmentedButton<LibraryTab>),
    matching: find.text(label),
  );

  testWidgets('tabs follow includeSavedObjects and the backups folder', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);

    expect(segment('Mods'), findsOneWidget);
    expect(segment('Saves'), findsOneWidget);
    expect(segment('Backups'), findsOneWidget);
    expect(segment('Saved Objects'), findsNothing);

    await container
        .read(libraryOptionsProvider.notifier)
        .setIncludeSavedObjects(true);
    await tester.pumpAndSettle();
    expect(segment('Saved Objects'), findsOneWidget);

    await container
        .read(libraryOptionsProvider.notifier)
        .setIncludeSavedObjects(false);
    await tester.pumpAndSettle();
    expect(segment('Saved Objects'), findsNothing);
  });

  testWidgets('no Backups tab without a backups folder', (tester) async {
    final noBackups = ProviderContainer.test(
      overrides: libraryPageOverrides(
        library: () => SpyLibraryController(library.state),
        store: store,
        directories: fixtureDirectories.copyWith(backupsDir: ''),
      ),
    );
    await pumpLibraryPage(tester, noBackups);

    expect(segment('Mods'), findsOneWidget);
    expect(segment('Saves'), findsOneWidget);
    expect(segment('Backups'), findsNothing);
  });

  testWidgets('switching to Backups swaps the toolbar, view and panel', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    expect(find.byType(ModsView), findsOneWidget);
    expect(find.byType(SelectedModPanel), findsOneWidget);

    await tester.tap(segment('Backups'));
    await tester.pumpAndSettle();

    expect(container.read(libraryTabProvider), LibraryTab.backups);
    expect(find.byType(BackupsView), findsOneWidget);
    expect(find.byType(ModsView), findsNothing);
    expect(find.byType(SelectedBackupPanel), findsOneWidget);
    expect(find.byType(SelectedModPanel), findsNothing);
    // Backups toolbar instead of the mods one.
    expect(find.text('Name A-Z'), findsOneWidget);
    expect(find.text('Import selected (0)'), findsOneWidget);
    expect(find.textContaining('Bulk actions'), findsNothing);
    expect(find.text('Select a backup'), findsOneWidget);
    // The fixture has no backups.
    expect(
      find.text('No backups found in ${fixtureDirectories.backupsDir}'),
      findsOneWidget,
    );

    await tester.tap(segment('Mods'));
    await tester.pumpAndSettle();
    expect(container.read(libraryTabProvider), LibraryTab.mods);
    expect(find.byType(ModsGridCard), findsNWidgets(5));
  });

  testWidgets('Backups tab falls back to Mods when the folder is removed', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    await tester.tap(segment('Backups'));
    await tester.pumpAndSettle();
    expect(container.read(libraryTabProvider), LibraryTab.backups);

    await container
        .read(directoriesProvider.notifier)
        .set(fixtureDirectories.copyWith(backupsDir: ''));
    await tester.pumpAndSettle();

    expect(container.read(libraryTabProvider), LibraryTab.mods);
    expect(segment('Backups'), findsNothing);
    expect(find.byType(ModsGridCard), findsNWidgets(5));
  });

  testWidgets('grid renders one card per mod of the selected type', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);

    expect(find.byType(ModsGridCard), findsNWidgets(5));
    expect(cardNamesOf(tester), [
      'Alpha Mod',
      'Beta Mod',
      'Delta Mod',
      'Epsilon Mod',
      'Gamma Mod',
    ]);
    // The save is not in the mods list.
    expect(find.text('My Save'), findsNothing);
    // Alpha has an image, so its name is not painted on the tile.
    expect(find.text('Alpha Mod'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ModsGridCard).first,
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(find.text('Bulk actions (5)'), findsOneWidget);
    expect(find.text('Select a mod'), findsOneWidget);
  });

  testWidgets('search filters after the debounce', (tester) async {
    await pumpLibraryPage(tester, container);

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump(searchDebounce + const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.byType(ModsGridCard), findsOneWidget);
    expect(find.text('Beta Mod'), findsOneWidget);
    expect(find.text('Bulk actions (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.byType(ModsGridCard), findsNWidgets(5));
  });

  testWidgets('no match shows the filters hint', (tester) async {
    await pumpLibraryPage(tester, container);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(searchDebounce + const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.byType(ModsGridCard), findsNothing);
    expect(find.text('No mods match the current filters'), findsOneWidget);
  });

  testWidgets('sort menu changes the order', (tester) async {
    await pumpLibraryPage(tester, container);

    await tester.tap(find.text('A-Z'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Missing assets'));
    await tester.pumpAndSettle();

    expect(cardNamesOf(tester), [
      'Epsilon Mod',
      'Beta Mod',
      'Gamma Mod',
      'Alpha Mod',
      'Delta Mod',
    ]);
    // The button now shows the active option.
    expect(find.text('Missing assets'), findsOneWidget);
  });

  testWidgets('folder filter narrows the grid and shows a badge', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Workshop'), findsOneWidget);

    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();

    expect(cardNamesOf(tester), ['Delta Mod', 'Gamma Mod']);
    // One active filter in the badge; the menu stays open.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Clear all filters'), findsOneWidget);

    await tester.tap(find.text('Clear all filters'));
    await tester.pumpAndSettle();
    expect(find.byType(ModsGridCard), findsNWidgets(5));
  });

  testWidgets('list/grid toggle switches the view and persists', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);

    await tester.tap(find.byTooltip('Show as list'));
    await tester.pumpAndSettle();

    expect(find.byType(ModsListItem), findsNWidgets(5));
    expect(find.byType(ModsGridCard), findsNothing);
    expect(find.text('Favourites'), findsNWidgets(2));
    expect(
      await store.read(LibraryViewOptionsController.storageKey),
      contains('"useListView":true'),
    );

    await tester.tap(find.byTooltip('Show as grid'));
    await tester.pumpAndSettle();
    expect(find.byType(ModsGridCard), findsNWidgets(5));
  });

  testWidgets('click selects, Ctrl-click toggles, Esc clears', (tester) async {
    await pumpLibraryPage(tester, container);
    final scheme = Theme.of(tester.element(find.byType(ModsGridCard).first))
        .colorScheme;

    Color borderColor(String name) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: card(name),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;
      return decoration.border!.top.color;
    }

    await tester.tap(card('Beta Mod'));
    await tester.pumpAndSettle();
    expect(container.read(selectionProvider), {library.beta.jsonPath});
    expect(borderColor('Beta Mod'), scheme.primary);
    expect(borderColor('Delta Mod'), Colors.transparent);
    expect(find.text('Beta Mod'), findsNWidgets(2)); // card + panel header
    // The panel shows the asset list (empty in this harness) and the
    // action bar for the selected mod.
    expect(find.text('No asset files referenced'), findsOneWidget);
    expect(find.text('Download all'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(card('Delta Mod'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(container.read(selectionProvider), {
      library.beta.jsonPath,
      library.delta.jsonPath,
    });
    expect(borderColor('Beta Mod'), scheme.primary);
    expect(borderColor('Delta Mod'), scheme.primary);
    expect(find.text('2 mods selected'), findsOneWidget);
    expect(find.text('Bulk actions (2)'), findsOneWidget);

    // Ctrl-click again removes it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(card('Delta Mod'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(container.read(selectionProvider), {library.beta.jsonPath});

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(selectionProvider), isEmpty);
    expect(find.text('Select a mod'), findsOneWidget);
    expect(borderColor('Beta Mod'), Colors.transparent);
  });

  testWidgets('Ctrl+F focuses the search field', (tester) async {
    await pumpLibraryPage(tester, container);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('right-click shows the mod menu with the expected items', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);

    // Beta: missing assets and a backup.
    await tester.tap(card('Beta Mod'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(container.read(selectionProvider), {library.beta.jsonPath});
    for (final label in [
      'Download',
      'View images',
      'Open in file explorer',
      'Open Steam Workshop page',
      'Update from Steam Workshop',
      'Copy name',
      'Copy filename',
      'Rename mod',
      'Delete',
      'Import backup',
      'Open backup in file explorer',
      'Copy backup filename',
      'Delete backup',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Save as Mod'), findsNothing);

    // Stubbed actions show the not-implemented snack bar (Download is live;
    // see test/features/downloads/presentation).
    await tester.tap(find.text('Import backup'));
    await tester.pumpAndSettle();
    expect(find.text('Import backup: not implemented yet'), findsOneWidget);

    // Delta: complete, no backup.
    await tester.tap(card('Delta Mod'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsNothing);
    expect(find.text('Import backup'), findsNothing);
    expect(find.text('Copy name'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('right-click on a save offers Save as Mod, no Workshop items', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);

    await tester.tap(find.text('Saves'));
    await tester.pumpAndSettle();
    expect(find.byType(ModsGridCard), findsOneWidget);
    expect(find.text('Select a save'), findsOneWidget);

    await tester.tap(find.byType(ModsGridCard), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Save as Mod'), findsOneWidget);
    expect(find.text('Rename save'), findsOneWidget);
    expect(find.text('Open Steam Workshop page'), findsNothing);
    expect(find.text('Update from Steam Workshop'), findsNothing);
  });

  testWidgets('Copy name puts the display name on the clipboard', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    final clipboardCalls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCalls.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(card('Gamma Mod'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy name'));
    await tester.pumpAndSettle();

    expect(clipboardCalls, [
      {'text': 'Gamma Mod'},
    ]);
    expect(find.text('Copied to clipboard'), findsOneWidget);
  });

  testWidgets('missing and audio badges follow the summary', (tester) async {
    await pumpLibraryPage(tester, container);

    expect(find.text('2 missing'), findsOneWidget);
    expect(find.text('1 missing'), findsOneWidget);
    expect(find.text('3 missing'), findsOneWidget);
    expect(find.text('0 missing'), findsNothing);
    expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    expect(
      find.descendant(
        of: card('Beta Mod'),
        matching: find.byIcon(Icons.audiotrack),
      ),
      findsOneWidget,
    );
  });

  testWidgets('backup badge is coloured by status and hides with the option', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);

    // Alpha, Beta and Gamma have backups; Delta and Epsilon do not.
    expect(find.byIcon(Icons.folder_zip_outlined), findsNWidgets(3));
    expect(
      find.descendant(
        of: card('Delta Mod'),
        matching: find.byIcon(Icons.folder_zip_outlined),
      ),
      findsNothing,
    );
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.descendant(
          of: card('Gamma Mod'),
          matching: find.byIcon(Icons.folder_zip_outlined),
        ),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('Asset count mismatch'));
    expect(tooltip.message, contains('9 assets in backup'));
    expect(tooltip.message, contains('2 asset files on disk'));

    await container
        .read(libraryViewOptionsProvider.notifier)
        .setShowBackupState(false);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.folder_zip_outlined), findsNothing);
  });

  testWidgets('switching the type clears the selection and search', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);

    await tester.tap(find.byType(ModsGridCard).first); // Alpha (A-Z)
    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump(searchDebounce + const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(find.byType(ModsGridCard), findsOneWidget);

    await tester.tap(find.text('Saves'));
    await tester.pumpAndSettle();

    expect(container.read(selectionProvider), isEmpty);
    expect(container.read(modFilterProvider).query, '');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.textContaining('My Save'), findsWidgets);
  });
}

/// Names of the grid cards in display order.
List<String> cardNamesOf(WidgetTester tester) => tester
    .widgetList<ModsGridCard>(find.byType(ModsGridCard))
    .map((c) => c.mod.saveName)
    .toList();
