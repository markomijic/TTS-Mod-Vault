import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_context_menu.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_badges.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_grid_card.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_list_item.dart';
import 'package:tts_mod_vault/features/backups/presentation/backups_view.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_view_options.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_grid_card.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/library_search_field.dart';

import '../library/presentation/presentation_test_harness.dart';
import 'backups_test_harness.dart';

void main() {
  late FixtureLibrary library;
  late FixtureBackups backups;
  late InMemoryKeyValueStore store;
  late ProviderContainer container;

  setUpAll(() {
    library = FixtureLibrary.create();
    backups = FixtureBackups(library);
  });
  tearDownAll(() => library.delete());

  setUp(() {
    store = InMemoryKeyValueStore();
    container = ProviderContainer.test(
      overrides: libraryPageOverrides(
        library: () => SpyLibraryController(backups.state),
        store: store,
      ),
    );
  });

  Finder segment(String label) => find.descendant(
    of: find.byType(SegmentedButton<LibraryTab>),
    matching: find.text(label),
  );

  Finder card(String fileName) => find.ancestor(
    of: find.text(fileName),
    matching: find.byType(BackupGridCard),
  );

  Finder menuItem(String label) => find.descendant(
    of: find.byType(PopupMenuItem<MenuAction>),
    matching: find.text(label),
  );

  List<String> cardNames(WidgetTester tester) => tester
      .widgetList<BackupGridCard>(find.byType(BackupGridCard))
      .map((c) => c.backup.fileName)
      .toList();

  Future<void> pumpBackupsTab(WidgetTester tester) async {
    await pumpLibraryPage(tester, container);
    await tester.tap(segment('Backups'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(searchDebounce + const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
  }

  testWidgets('grid renders one card per backup, A-Z, with details', (
    tester,
  ) async {
    await pumpBackupsTab(tester);

    expect(find.byType(BackupsView), findsOneWidget);
    expect(find.byType(BackupGridCard), findsNWidgets(5));
    expect(cardNames(tester), [
      'Alpha Mod.ttsmod',
      'Beta Mod.ttsmod',
      'Gamma Mod.ttsmod',
      'Old Thing.ttsmod',
      'Zeta Pack.ttsmod',
    ]);
    expect(find.text('3.0 MB · Weekly'), findsOneWidget);
    expect(find.text('1.5 MB · Archive'), findsOneWidget);
    expect(
      find.text(modDateFormat.format(backups.zetaPack.modified)),
      findsOneWidget,
    );
    // Toolbar: backups controls, no mods controls.
    expect(find.text('Name A-Z'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Import selected (5)'), findsOneWidget);
    expect(find.byTooltip('Show as list'), findsOneWidget);
    expect(find.textContaining('Bulk actions'), findsNothing);
    expect(find.text('Select a backup'), findsOneWidget);
    // The tab tooltip counts the backups.
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byType(SegmentedButton<LibraryTab>),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('5 backups'));
  });

  testWidgets('match badge is coloured by whether a mod matches', (
    tester,
  ) async {
    await pumpBackupsTab(tester);
    final colors = VaultColors.of(
      tester.element(find.byType(BackupGridCard).first),
    );

    Color badgeColor(String fileName) {
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.descendant(
            of: card(fileName),
            matching: find.byType(BackupMatchBadge),
          ),
          matching: find.byType(Icon),
        ),
      );
      return icon.color!;
    }

    expect(badgeColor('Alpha Mod.ttsmod'), colors.backupUpToDate);
    expect(badgeColor('Old Thing.ttsmod'), colors.backupNone);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.descendant(
          of: card('Zeta Pack.ttsmod'),
          matching: find.byIcon(Icons.extension_off_outlined),
        ),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('No matching mod'));
    expect(tooltip.message, contains('12.0 MB'));
    expect(tooltip.message, contains('20 assets in backup'));
  });

  testWidgets('search filters by file name after the debounce', (tester) async {
    await pumpBackupsTab(tester);

    await search(tester, 'zeta');
    expect(cardNames(tester), ['Zeta Pack.ttsmod']);
    expect(find.text('Import selected (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.byType(BackupGridCard), findsNWidgets(5));
  });

  testWidgets('each sort option orders the grid', (tester) async {
    await pumpBackupsTab(tester);
    const expected = {
      'Name Z-A': [
        'Zeta Pack.ttsmod',
        'Old Thing.ttsmod',
        'Gamma Mod.ttsmod',
        'Beta Mod.ttsmod',
        'Alpha Mod.ttsmod',
      ],
      'Largest first': [
        'Zeta Pack.ttsmod',
        'Beta Mod.ttsmod',
        'Alpha Mod.ttsmod',
        'Gamma Mod.ttsmod',
        'Old Thing.ttsmod',
      ],
      'Smallest first': [
        'Old Thing.ttsmod',
        'Gamma Mod.ttsmod',
        'Alpha Mod.ttsmod',
        'Beta Mod.ttsmod',
        'Zeta Pack.ttsmod',
      ],
      'Newest first': [
        'Zeta Pack.ttsmod',
        'Alpha Mod.ttsmod',
        'Beta Mod.ttsmod',
        'Gamma Mod.ttsmod',
        'Old Thing.ttsmod',
      ],
      'Oldest first': [
        'Old Thing.ttsmod',
        'Gamma Mod.ttsmod',
        'Beta Mod.ttsmod',
        'Alpha Mod.ttsmod',
        'Zeta Pack.ttsmod',
      ],
      'Name A-Z': [
        'Alpha Mod.ttsmod',
        'Beta Mod.ttsmod',
        'Gamma Mod.ttsmod',
        'Old Thing.ttsmod',
        'Zeta Pack.ttsmod',
      ],
    };
    var current = 'Name A-Z';
    for (final MapEntry(key: label, value: order) in expected.entries) {
      await tester.tap(find.text(current)); // the sort button
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last); // the menu item
      await tester.pumpAndSettle();
      expect(cardNames(tester), order, reason: label);
      expect(find.text(label), findsOneWidget, reason: label);
      current = label;
    }
  });

  testWidgets('folder and match filters narrow the grid with a badge', (
    tester,
  ) async {
    await pumpBackupsTab(tester);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Has matching mod'), findsOneWidget);
    expect(find.text('No matching mod'), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(cardNames(tester), ['Gamma Mod.ttsmod', 'Old Thing.ttsmod']);
    expect(find.text('1'), findsOneWidget); // badge; the menu stays open

    await tester.tap(find.text('No matching mod'));
    await tester.pumpAndSettle();
    expect(cardNames(tester), ['Old Thing.ttsmod']);
    expect(find.text('2'), findsOneWidget);
    expect(container.read(backupFilterProvider).hasFilters, isTrue);

    await tester.tap(find.text('Clear all filters'));
    await tester.pumpAndSettle();
    expect(find.byType(BackupGridCard), findsNWidgets(5));
    expect(container.read(backupFilterProvider).hasFilters, isFalse);
  });

  testWidgets('list/grid toggle is persisted separately from the mods one', (
    tester,
  ) async {
    await pumpBackupsTab(tester);

    await tester.tap(find.byTooltip('Show as list'));
    await tester.pumpAndSettle();

    expect(find.byType(BackupListItem), findsNWidgets(5));
    expect(find.byType(BackupGridCard), findsNothing);
    expect(find.text('Weekly'), findsNWidgets(3));
    final stored = await store.read(LibraryViewOptionsController.storageKey);
    expect(stored, contains('"useBackupsListView":true'));
    expect(stored, contains('"useListView":false'));

    // The mods tabs still use the grid.
    await tester.tap(segment('Mods'));
    await tester.pumpAndSettle();
    expect(find.byType(ModsGridCard), findsNWidgets(5));
    expect(find.byTooltip('Show as list'), findsOneWidget);

    await tester.tap(segment('Backups'));
    await tester.pumpAndSettle();
    expect(find.byType(BackupListItem), findsNWidgets(5));
    await tester.tap(find.byTooltip('Show as grid'));
    await tester.pumpAndSettle();
    expect(find.byType(BackupGridCard), findsNWidgets(5));
  });

  testWidgets('click selects, Ctrl-click toggles, Esc clears', (tester) async {
    await pumpBackupsTab(tester);
    final scheme = Theme.of(tester.element(find.byType(BackupGridCard).first))
        .colorScheme;

    Color borderColor(String fileName) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: card(fileName),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;
      return decoration.border!.top.color;
    }

    await tester.tap(card('Alpha Mod.ttsmod'));
    await tester.pumpAndSettle();
    expect(container.read(backupSelectionProvider), {backups.alpha.path});
    expect(borderColor('Alpha Mod.ttsmod'), scheme.primary);
    expect(borderColor('Beta Mod.ttsmod'), Colors.transparent);
    // Card band + panel header.
    expect(find.text('Alpha Mod.ttsmod'), findsNWidgets(2));
    expect(find.text('Import selected (1)'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(card('Beta Mod.ttsmod'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(container.read(backupSelectionProvider), {
      backups.alpha.path,
      backups.beta.path,
    });
    expect(borderColor('Beta Mod.ttsmod'), scheme.primary);
    expect(find.text('2 backups selected'), findsOneWidget);
    expect(find.text('Import selected (2)'), findsOneWidget);

    // Ctrl-click again removes it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(card('Beta Mod.ttsmod'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(container.read(backupSelectionProvider), {backups.alpha.path});

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(backupSelectionProvider), isEmpty);
    expect(find.text('Select a backup'), findsOneWidget);
    expect(borderColor('Alpha Mod.ttsmod'), Colors.transparent);
    // The mod selection is untouched by backup clicks.
    expect(container.read(selectionProvider), isEmpty);
  });

  testWidgets('right-click selects and shows the five menu items', (
    tester,
  ) async {
    await pumpBackupsTab(tester);

    await tester.tap(card('Gamma Mod.ttsmod'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(container.read(backupSelectionProvider), {backups.gamma.path});
    for (final label in [
      'Import backup',
      'Open in file explorer',
      'Copy filename',
      'Rename backup…',
      'Delete backup',
    ]) {
      expect(menuItem(label), findsOneWidget, reason: label);
    }
    expect(find.byType(PopupMenuItem<MenuAction>), findsNWidgets(5));

    // The actions themselves are covered by the presentation wiring tests.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<MenuAction>), findsNothing);
  });

  testWidgets('details panel lists the backup and its matching mod', (
    tester,
  ) async {
    await pumpBackupsTab(tester);

    await tester.tap(card('Alpha Mod.ttsmod'));
    await tester.pumpAndSettle();

    expect(find.text('Folder'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Path'), findsOneWidget);
    expect(find.text(backups.alpha.path), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
    expect(find.text('Modified'), findsOneWidget);
    expect(
      find.text(modDateFormat.format(backups.alpha.modified)),
      findsNWidgets(2), // card + panel
    );
    expect(find.text('Assets in backup'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Matching mod'), findsOneWidget);
    expect(find.text('Alpha Mod'), findsOneWidget);
    expect(find.text('Show mod'), findsOneWidget);
    for (final label in [
      'Import backup',
      'Open in file explorer',
      'Copy filename',
      'Rename backup…',
      'Delete backup',
    ]) {
      expect(
        find.widgetWithText(FilledButton, label),
        findsOneWidget,
        reason: label,
      );
    }

    // An unmatched backup says so and offers no "Show mod".
    await tester.tap(card('Old Thing.ttsmod'));
    await tester.pumpAndSettle();
    expect(find.text('Old Thing.ttsmod'), findsNWidgets(2));
    expect(find.text('No matching mod'), findsOneWidget);
    expect(find.text('Show mod'), findsNothing);
    expect(find.text('Archive'), findsOneWidget);
  });

  testWidgets('Show mod switches to the mod tab and selects the mod', (
    tester,
  ) async {
    await pumpBackupsTab(tester);
    await tester.tap(card('Gamma Mod.ttsmod'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show mod'));
    await tester.pumpAndSettle();

    expect(container.read(libraryTabProvider), LibraryTab.mods);
    expect(container.read(selectionProvider), {library.gamma.jsonPath});
    expect(find.byType(ModsGridCard), findsNWidgets(5));
    expect(find.byType(BackupGridCard), findsNothing);
    // Selected-mod panel header plus the card tile.
    expect(find.text('Gamma Mod'), findsNWidgets(2));
    expect(find.text('Download all'), findsOneWidget);
    // Leaving the Backups tab cleared the backup selection.
    expect(container.read(backupSelectionProvider), isEmpty);
  });

  testWidgets('Copy filename copies the name without the extension', (
    tester,
  ) async {
    await pumpBackupsTab(tester);
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

    // From the context menu.
    await tester.tap(card('Alpha Mod.ttsmod'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Copy filename'));
    await tester.pumpAndSettle();
    expect(clipboardCalls, [
      {'text': 'Alpha Mod'},
    ]);
    expect(find.text('Copied to clipboard'), findsOneWidget);

    // From the panel button.
    await tester.tap(card('Zeta Pack.ttsmod'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Copy filename'));
    await tester.pumpAndSettle();
    expect(clipboardCalls, [
      {'text': 'Alpha Mod'},
      {'text': 'Zeta Pack'},
    ]);
  });

  testWidgets('Ctrl+F focuses the backups search field', (tester) async {
    await pumpBackupsTab(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('no match shows the filters hint', (tester) async {
    await pumpBackupsTab(tester);

    await search(tester, 'zzz');

    expect(find.byType(BackupGridCard), findsNothing);
    expect(find.text('No backups match the current filters'), findsOneWidget);
    expect(find.text('Import selected (0)'), findsOneWidget);
  });

  testWidgets('an empty backups folder shows where it looked', (tester) async {
    final empty = ProviderContainer.test(
      overrides: libraryPageOverrides(
        library: () => SpyLibraryController(library.state),
        store: store,
      ),
    );
    await pumpLibraryPage(tester, empty);
    await tester.tap(segment('Backups'));
    await tester.pumpAndSettle();

    expect(find.byType(BackupGridCard), findsNothing);
    expect(
      find.text('No backups found in ${fixtureDirectories.backupsDir}'),
      findsOneWidget,
    );
  });
}
