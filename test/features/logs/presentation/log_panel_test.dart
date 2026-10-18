// The log panel docked under the library list: collapsed header with
// preview and unseen badge, expand/collapse, filters, search, copy, clear,
// follow-tail with "Jump to latest", row click selecting the mod, the log
// file actions, the resize handle, and the no-auto-expand rule.

import 'dart:convert' show jsonDecode;

import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_page.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/debounced_search_field.dart';
import 'package:tts_mod_vault/features/logs/application/log_providers.dart';
import 'package:tts_mod_vault/features/logs/presentation/log_entry_row.dart';
import 'package:tts_mod_vault/features/logs/presentation/log_panel.dart';
import 'package:tts_mod_vault/features/logs/presentation/log_panel_header.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_progress_bar.dart';

import '../../library/presentation/presentation_test_harness.dart';

void main() {
  late FixtureLibrary library;
  late InMemoryKeyValueStore store;
  late AppLog log;
  late ProviderContainer container;

  setUpAll(() => library = FixtureLibrary.create());
  tearDownAll(() => library.delete());

  setUp(() {
    store = InMemoryKeyValueStore();
    log = AppLog(store: LogStore());
    container = ProviderContainer.test(
      overrides: libraryPageOverrides(
        library: () => SpyLibraryController(library.state),
        store: store,
        log: log,
      ),
    );
    addTearDown(log.dispose);
  });

  /// Publishes the store's entries to the panel without waiting for the
  /// coalescing timer, and lets the UI settle.
  Future<void> flush(WidgetTester tester) async {
    container.read(logEntriesProvider.notifier).flush();
    await tester.pumpAndSettle();
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Expand log'));
    await tester.pumpAndSettle();
  }

  Finder inPanel(Finder finder) =>
      find.descendant(of: find.byType(LogPanel), matching: finder);

  /// The [IconButton] whose tooltip is [tooltip] (`byTooltip` finds the
  /// Tooltip widget inside the button).
  IconButton iconButton(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );

  LogPanelHeader header(WidgetTester tester) =>
      tester.widget<LogPanelHeader>(find.byType(LogPanelHeader));

  Badge badge(WidgetTester tester) => tester.widget<Badge>(
    find.ancestor(of: find.text('Log'), matching: find.byType(Badge)),
  );

  List<Object?> mockClipboard(WidgetTester tester) {
    final calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') calls.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

  Future<void> logThree(WidgetTester tester) async {
    log.info(LogSource.library, 'alpha msg');
    log.error(LogSource.download, 'beta msg', details: 'HTTP 404');
    log.warning(LogSource.backup, 'gamma msg');
    log.debugLog(LogSource.debug, 'debug msg');
    await flush(tester);
  }

  testWidgets('the bottom slot is the progress bar over the collapsed log', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);

    final slot = find.byType(LibraryBottomSlot);
    expect(slot, findsOneWidget);
    expect(
      find.descendant(of: slot, matching: find.byType(OperationProgressBar)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: slot, matching: find.byType(LogPanel)),
      findsOneWidget,
    );
    expect(find.text('Log'), findsOneWidget);
    expect(find.byTooltip('Expand log'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(badge(tester).isLabelVisible, isFalse);
  });

  testWidgets('collapsed: preview of the latest entry, badge and flash on '
      'error, never auto-expands', (tester) async {
    await pumpLibraryPage(tester, container);
    log.info(LogSource.library, 'hello there');
    await flush(tester);

    expect(find.text('hello there'), findsOneWidget);
    expect(badge(tester).isLabelVisible, isFalse);
    expect(header(tester).flashing, isFalse);

    log.error(LogSource.download, 'boom');
    container.read(logEntriesProvider.notifier).flush();
    await tester.pump();

    expect(header(tester).flashing, isTrue, reason: 'flashes once');
    expect(badge(tester).isLabelVisible, isTrue);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget, reason: 'preview follows');
    expect(find.text('hello there'), findsNothing);
    expect(container.read(logPanelStateProvider).expanded, isFalse);
    expect(find.byType(FilterChip), findsNothing);

    await tester.pumpAndSettle();
    expect(header(tester).flashing, isFalse, reason: 'flash is one pulse');
    expect(badge(tester).isLabelVisible, isTrue, reason: 'badge stays');

    log.warning(LogSource.backup, 'careful');
    await flush(tester);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('expanding marks entries seen, lists newest at the bottom and '
      'persists', (tester) async {
    await pumpLibraryPage(tester, container);
    log.info(LogSource.library, 'first');
    log.error(LogSource.download, 'second');
    await flush(tester);
    expect(badge(tester).isLabelVisible, isTrue);

    await expand(tester);

    expect(container.read(logPanelStateProvider).expanded, isTrue);
    expect(badge(tester).isLabelVisible, isFalse);
    expect(container.read(unseenLogCountProvider), 0);
    expect(find.byType(FilterChip), findsWidgets);
    expect(find.text('2 entries'), findsOneWidget);
    expect(find.byType(LogEntryRow), findsNWidgets(2));
    expect(
      tester.getCenter(find.text('second')).dy,
      greaterThan(tester.getCenter(find.text('first')).dy),
    );
    final json = jsonDecode((await store.read('logPanel'))!) as Map;
    expect(json['expanded'], isTrue);

    // An error while expanded does not count as unseen.
    log.error(LogSource.download, 'third');
    await flush(tester);
    expect(badge(tester).isLabelVisible, isFalse);

    await tester.tap(find.byTooltip('Collapse log'));
    await tester.pumpAndSettle();
    expect(find.byType(LogEntryRow), findsNothing);
    expect(find.text('third'), findsOneWidget, reason: 'preview');
  });

  testWidgets('level chips, source menu, debug toggle and search filter', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    await logThree(tester);
    await expand(tester);

    expect(find.text('alpha msg'), findsOneWidget);
    expect(find.text('beta msg'), findsOneWidget);
    expect(find.text('gamma msg'), findsOneWidget);
    expect(find.text('debug msg'), findsNothing);
    expect(find.text('3 entries'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Error'));
    await tester.pumpAndSettle();
    expect(find.text('alpha msg'), findsNothing);
    expect(find.text('beta msg'), findsOneWidget);
    expect(find.text('gamma msg'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Error'));
    await tester.pumpAndSettle();
    expect(find.byType(LogEntryRow), findsNWidgets(3));

    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Backup'));
    await tester.pumpAndSettle();
    expect(find.text('gamma msg'), findsOneWidget);
    expect(find.text('beta msg'), findsNothing);
    expect(container.read(logFilterProvider).sources, {LogSource.backup});
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Backup'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(LogEntryRow), findsNWidgets(3));

    await tester.tap(find.widgetWithText(FilterChip, 'Show debug'));
    await tester.pumpAndSettle();
    expect(find.text('debug msg'), findsOneWidget);
    expect(find.text('4 entries'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Show debug'));
    await tester.pumpAndSettle();

    await tester.enterText(inPanel(find.byType(TextField)), 'alpha');
    await tester.pump(searchDebounce + const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('alpha msg'), findsOneWidget);
    expect(find.byType(LogEntryRow), findsOneWidget);
    expect(find.text('1 entry'), findsOneWidget);
  });

  testWidgets('details expand, copy entry via right-click', (tester) async {
    await pumpLibraryPage(tester, container);
    final clipboard = mockClipboard(tester);
    await logThree(tester);
    await expand(tester);

    expect(find.text('HTTP 404'), findsNothing);
    await tester.tap(find.byTooltip('Show details'));
    await tester.pumpAndSettle();
    expect(find.text('HTTP 404'), findsOneWidget);

    await tester.tap(find.text('gamma msg'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy entry'));
    await tester.pumpAndSettle();
    expect(clipboard, hasLength(1));
    final text = (clipboard.single! as Map)['text'] as String;
    expect(text, contains('[WARNING] [backup] gamma msg'));
  });

  testWidgets('copy visible and clear with confirmation', (tester) async {
    await pumpLibraryPage(tester, container);
    final clipboard = mockClipboard(tester);
    await logThree(tester);
    await expand(tester);

    await tester.tap(find.byTooltip('Copy visible entries'));
    await tester.pumpAndSettle();
    final text = (clipboard.single! as Map)['text'] as String;
    expect(text.split('\n'), hasLength(3));
    expect(text, contains('alpha msg'));
    expect(text, contains('gamma msg'));
    expect(text, isNot(contains('debug msg')));

    await tester.tap(find.byTooltip('Clear log'));
    await tester.pumpAndSettle();
    expect(find.text('Clear the log?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(LogEntryRow), findsNWidgets(3));

    await tester.tap(find.byTooltip('Clear log'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear log'));
    await tester.pumpAndSettle();
    expect(find.byType(LogEntryRow), findsNothing);
    expect(find.text('No log entries'), findsOneWidget);
    expect(log.store.length, 0);
    expect(iconButton(tester, 'Clear log').onPressed, isNull);
  });

  testWidgets('follows the tail until the user scrolls up; Jump to latest', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    for (var i = 0; i < 200; i++) {
      log.info(LogSource.library, 'line $i');
    }
    await flush(tester);
    await expand(tester);

    expect(find.text('line 199'), findsOneWidget);
    expect(find.text('line 0'), findsNothing);
    expect(find.text('Jump to latest'), findsNothing);

    log.info(LogSource.library, 'line 200');
    await flush(tester);
    expect(find.text('line 200'), findsOneWidget, reason: 'follow-tail');

    await tester.drag(inPanel(find.byType(ListView)), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('Jump to latest'), findsOneWidget);
    expect(find.text('line 200'), findsNothing);

    log.info(LogSource.library, 'line 201');
    await flush(tester);
    expect(find.text('line 201'), findsNothing, reason: 'view holds still');
    expect(find.text('Jump to latest'), findsOneWidget);

    await tester.tap(find.text('Jump to latest'));
    await tester.pumpAndSettle();
    expect(find.text('line 201'), findsOneWidget);
    expect(find.text('Jump to latest'), findsNothing);
  });

  testWidgets('clicking a row selects its mod and switches tab', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    log.success(
      LogSource.backup,
      'Backed up My Save',
      modPath: library.save.jsonPath,
    );
    log.error(
      LogSource.download,
      'Gone mod',
      modPath: '${fixtureDirectories.workshopDir}/999.json',
    );
    log.info(LogSource.app, 'no mod here');
    await flush(tester);
    await expand(tester);

    await tester.tap(find.text('Backed up My Save'));
    await tester.pumpAndSettle();
    expect(container.read(libraryTabProvider), LibraryTab.saves);
    expect(container.read(selectionProvider), {library.save.jsonPath});

    await tester.tap(find.text('Gone mod'));
    await tester.pumpAndSettle();
    expect(
      find.text('The mod this entry refers to is no longer in the library'),
      findsOneWidget,
    );
    expect(container.read(selectionProvider), {library.save.jsonPath});

    final plain = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('no mod here'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(plain.onTap, isNull);
  });

  testWidgets('Open log file is disabled without a file sink', (tester) async {
    await pumpLibraryPage(tester, container);
    expect(iconButton(tester, 'Open log file').onPressed, isNull);

    await tester.tap(find.byTooltip('Log file actions'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MenuItemButton>(
            find.widgetWithText(MenuItemButton, 'Copy log file path'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('with a log file the path can be copied', (tester) async {
    const path = '/logs/vault.log';
    container = ProviderContainer.test(
      overrides: [
        ...libraryPageOverrides(
          library: () => SpyLibraryController(library.state),
          log: log,
        ),
        logFilePathProvider.overrideWithValue(path),
      ],
    );
    await pumpLibraryPage(tester, container);
    final clipboard = mockClipboard(tester);

    expect(iconButton(tester, 'Open log file').onPressed, isNotNull);

    await tester.tap(find.byTooltip('Log file actions'));
    await tester.pumpAndSettle();
    expect(find.text('Open log folder'), findsOneWidget);
    await tester.tap(find.text('Copy log file path'));
    await tester.pumpAndSettle();
    expect(clipboard, [
      {'text': path},
    ]);
  });

  testWidgets('the drag handle resizes the panel and persists the height', (
    tester,
  ) async {
    await pumpLibraryPage(tester, container);
    await expand(tester);
    final before = container.read(logPanelStateProvider).height;
    expect(before, LogPanelState.defaultHeight);

    await tester.drag(
      find.byTooltip('Drag to resize'),
      const Offset(0, -100),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    final after = container.read(logPanelStateProvider).height;
    expect(after, greaterThan(before));
    expect(after, lessThanOrEqualTo(before + 100));
    final json = jsonDecode((await store.read('logPanel'))!) as Map;
    expect(json['height'], after);
  });
}
