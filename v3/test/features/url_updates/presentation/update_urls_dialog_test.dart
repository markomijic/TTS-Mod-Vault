// The Update URLs dialog: presets, validation, the help dialog, and Apply
// going to the UrlUpdatesService for the single-mod button and to the
// BulkService for the bulk menu.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_failures_dialog.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/bulk_actions_button.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart'
    show urlReplacementPresetsProvider;
import 'package:tts_mod_vault/features/url_updates/application/url_updates_service.dart';
import 'package:tts_mod_vault/features/url_updates/presentation/update_urls_dialog.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations_en.dart';

import '../../bulk/presentation/fake_bulk_service.dart';
import '../../library/presentation/presentation_test_harness.dart';
import 'fake_url_updates_service.dart';

const pastebin = UrlReplacementPreset(
  label: 'Pastebin',
  oldUrl: 'http://pastebin.com/raw.php?i=|http://pastebin.com/raw/',
  newUrl: 'https://pastebin.com/raw/',
);

void main() {
  late FixtureLibrary library;
  late ProviderContainer container;
  late FakeUrlUpdatesService urlService;
  late FakeBulkService bulkService;

  setUpAll(() => library = FixtureLibrary.create());
  tearDownAll(() => library.delete());

  setUp(() {
    container = ProviderContainer.test(
      overrides: [
        ...libraryPageOverrides(
          library: () => SpyLibraryController(library.state),
        ),
        fakeUrlUpdatesServiceOverride(),
        fakeBulkServiceOverride(),
        urlReplacementPresetsProvider.overrideWithValue(const [pastebin]),
      ],
    );
    urlService =
        container.read(urlUpdatesServiceProvider) as FakeUrlUpdatesService;
    bulkService = container.read(bulkServiceProvider) as FakeBulkService;
  });

  Finder field(String label) => find.widgetWithText(TextField, label);

  FilledButton applyButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'));

  Future<void> openSingle(WidgetTester tester) async {
    container.read(selectionProvider.notifier).select(library.alpha.jsonPath);
    await pumpLibraryPage(tester, container);
    await tester.tap(find.widgetWithText(FilledButton, 'Update URLs'));
    await tester.pumpAndSettle();
  }

  Future<void> openBulk(WidgetTester tester) async {
    await pumpLibraryPage(tester, container);
    await tester.tap(find.byType(BulkActionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Update URLs'));
    await tester.pumpAndSettle();
  }

  group('validation', () {
    final l10n = AppLocalizationsEn();

    test('validateUpdateUrls', () {
      expect(validateUpdateUrls(l10n, oldPrefixes: const [], newPrefix: ''), (
        oldError: 'Enter at least one old prefix',
        newError: 'Enter the new prefix',
      ));
      expect(
        validateUpdateUrls(l10n, oldPrefixes: const ['a'], newPrefix: 'b|c'),
        (
          oldError: null,
          newError: 'Enter exactly one new prefix, without the | symbol',
        ),
      );
      expect(
        validateUpdateUrls(l10n, oldPrefixes: const ['a', 'b'], newPrefix: 'a'),
        (
          oldError: null,
          newError: 'The new prefix must differ from the old prefixes',
        ),
      );
      expect(
        validateUpdateUrls(l10n, oldPrefixes: const ['a'], newPrefix: 'b'),
        (oldError: null, newError: null),
      );
    });

    testWidgets('Apply stays disabled until the input is valid', (
      tester,
    ) async {
      await openSingle(tester);
      expect(find.byType(UpdateUrlsDialog), findsOneWidget);
      expect(find.text('1 mod will be updated.'), findsOneWidget);
      expect(applyButton(tester).onPressed, isNull);

      await tester.enterText(field('Old prefixes'), 'http://a/|http://b/');
      await tester.enterText(field('New prefix'), 'http://a/');
      await tester.pumpAndSettle();
      expect(
        find.text('The new prefix must differ from the old prefixes'),
        findsOneWidget,
      );
      expect(applyButton(tester).onPressed, isNull);

      await tester.enterText(field('New prefix'), 'http://x/|http://y/');
      await tester.pumpAndSettle();
      expect(
        find.text('Enter exactly one new prefix, without the | symbol'),
        findsOneWidget,
      );
      expect(applyButton(tester).onPressed, isNull);

      await tester.enterText(field('New prefix'), 'https://c/');
      await tester.pumpAndSettle();
      expect(applyButton(tester).onPressed, isNotNull);
    });

    testWidgets('the help icon opens the explanation', (tester) async {
      await openSingle(tester);
      await tester.tap(find.byTooltip('How Update URLs works'));
      await tester.pumpAndSettle();
      expect(find.text('How Update URLs works'), findsOneWidget);
      expect(find.textContaining('| pipe symbol'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateUrlsDialog), findsOneWidget);
    });
  });

  group('single mod', () {
    testWidgets('a preset fills the fields; Apply calls the URL service', (
      tester,
    ) async {
      await openSingle(tester);
      expect(find.text('Custom'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pastebin').last);
      await tester.pumpAndSettle();

      expect(find.text(pastebin.oldUrl), findsOneWidget);
      expect(find.text(pastebin.newUrl), findsOneWidget);
      expect(find.text('Pastebin'), findsOneWidget);
      expect(applyButton(tester).onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(bulkService.updateUrlsCalls, isEmpty);
      final call = urlService.calls.single;
      expect(call.mods.map((m) => m.jsonPath), [library.alpha.jsonPath]);
      expect(call.oldPrefixes, [
        'http://pastebin.com/raw.php?i=',
        'http://pastebin.com/raw/',
      ]);
      expect(call.newPrefix, 'https://pastebin.com/raw/');
      expect(call.renameFiles, isTrue);
      expect(find.text('Updated 1 mod, renamed 2 files'), findsOneWidget);
    });

    testWidgets('editing a field switches the preset back to Custom', (
      tester,
    ) async {
      await openSingle(tester);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pastebin').last);
      await tester.pumpAndSettle();
      expect(find.text('Custom'), findsNothing);

      await tester.enterText(field('New prefix'), 'https://other/');
      await tester.pumpAndSettle();
      expect(find.text('Custom'), findsOneWidget);
    });
  });

  group('bulk', () {
    testWidgets('Apply calls the bulk service with the dialog choices', (
      tester,
    ) async {
      await openBulk(tester);
      expect(find.text('5 mods will be updated.'), findsOneWidget);
      expect(
        find.text('This edits the JSON files of the mods.'),
        findsOneWidget,
      );

      await tester.enterText(field('Old prefixes'), 'http://a/ | http://b/');
      await tester.enterText(field('New prefix'), 'https://c/');
      await tester.tap(find.text('Rename cached files to match the new URLs'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(urlService.calls, isEmpty);
      final call = bulkService.updateUrlsCalls.single;
      expect(call.mods, hasLength(5));
      expect(call.oldPrefixes, ['http://a/', 'http://b/']);
      expect(call.newPrefix, 'https://c/');
      expect(call.renameFiles, isFalse);
      expect(find.text('Updated 5 mods'), findsOneWidget);
    });

    testWidgets('failures open the results dialog', (tester) async {
      bulkService.updateUrlsResult = UpdateUrlsResult(
        modsProcessed: 5,
        modsUpdated: 3,
        filesRenamed: 1,
        failed: [(library.gamma.jsonPath, 'read-only file')],
        cancelled: false,
      );
      await openBulk(tester);
      await tester.enterText(field('Old prefixes'), 'http://a/');
      await tester.enterText(field('New prefix'), 'https://c/');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(find.byType(BulkFailuresDialog), findsOneWidget);
      expect(find.text('Updated 3 mods, renamed 1 files'), findsOneWidget);
      final dialog = find.byType(BulkFailuresDialog);
      Finder inDialog(String text) =>
          find.descendant(of: dialog, matching: find.text(text));
      expect(inDialog('1 mod failed'), findsOneWidget);
      expect(inDialog('Gamma Mod'), findsOneWidget);
      expect(inDialog('read-only file'), findsOneWidget);
    });

    testWidgets('Cancel calls nothing', (tester) async {
      await openBulk(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(bulkService.updateUrlsCalls, isEmpty);
      expect(find.byType(UpdateUrlsDialog), findsNothing);
    });
  });
}
