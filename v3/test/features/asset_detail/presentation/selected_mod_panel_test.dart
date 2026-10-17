import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/asset_detail/application/asset_detail_filter.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_detail_view_options.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_list.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_toolbar.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_url_row.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/multi_select_view.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_view.dart';

import 'asset_detail_test_harness.dart';

void main() {
  late AssetDetailHarness h;

  setUp(() async => h = await AssetDetailHarness.create());

  Finder header(String label) => find.descendant(
    of: find.byType(AssetGroupHeader),
    matching: find.text(label),
  );

  Finder chip(String label) => find.widgetWithText(FilterChip, label);

  /// The download icons inside group headers ("Download all" has one too).
  final headerDownloadIcons = find.descendant(
    of: find.byType(AssetGroupHeader),
    matching: find.byIcon(Icons.download_outlined),
  );

  Finder urlRow(Asset asset) => find.widgetWithText(AssetUrlRow, asset.url);

  Color urlColor(WidgetTester tester, Asset asset) =>
      tester.widget<Text>(find.text(asset.url)).style!.color!;

  Future<void> rightClick(WidgetTester tester, Asset asset) async {
    await tester.tap(urlRow(asset), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  Future<void> closeMenu(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  group('dispatch', () {
    testWidgets('nothing selected shows the empty header with help', (
      tester,
    ) async {
      await pumpPanel(tester, h);

      expect(find.text('Select a mod'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byType(SelectedModView), findsNothing);
      expect(find.byType(MultiSelectView), findsNothing);
    });

    testWidgets('two selected shows the multi-select view with stubs', (
      tester,
    ) async {
      h.selectMany([h.fixture.alpha, h.fixture.beta]);
      await pumpPanel(tester, h);

      expect(find.byType(MultiSelectView), findsOneWidget);
      expect(find.text('2 mods selected'), findsOneWidget);
      expect(find.text('Alpha Mod'), findsOneWidget);
      expect(find.text('Beta Mod'), findsOneWidget);
      // Both are Workshop mods, so "Update mods" is offered.
      expect(find.text('Update mods'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsNothing);

      await tester.tap(find.text('Download & backup'));
      await tester.pumpAndSettle();
      expect(
        find.text('Download & backup: not implemented yet'),
        findsOneWidget,
      );
    });

    testWidgets('a save shows file name over its name', (tester) async {
      h.select(h.fixture.save);
      await pumpPanel(tester, h);

      expect(find.text('TS_Save_12.json\nMy Save'), findsOneWidget);
      expect(urlRow(h.fixture.s1), findsOneWidget);
    });
  });

  group('asset list', () {
    testWidgets('headers only for the types the mod references', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      expect(find.byType(AssetGroupHeader), findsNWidgets(5));
      for (final label in [
        'Asset bundles',
        'Audio',
        'Images',
        'Models',
        'PDFs',
      ]) {
        expect(header(label), findsOneWidget, reason: label);
      }
      expect(find.byType(AssetUrlRow), findsNWidgets(6));
      // The first header has no top padding, the others do.
      final headers = tester
          .widgetList<AssetGroupHeader>(find.byType(AssetGroupHeader))
          .toList();
      expect(headers.first.row.isFirst, isTrue);
      expect(headers.skip(1).every((hdr) => !hdr.row.isFirst), isTrue);
      // Only groups with missing files get the download icon.
      expect(headerDownloadIcons, findsNWidgets(3));

      h.select(h.fixture.beta);
      await tester.pumpAndSettle();

      expect(find.byType(AssetGroupHeader), findsOneWidget);
      expect(header('Images'), findsOneWidget);
      expect(find.text('Models'), findsNothing);
      expect(find.byType(AssetUrlRow), findsOneWidget);
    });

    testWidgets('status filter hides downloaded or missing assets', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(urlRow(h.fixture.img1), findsNothing);
      expect(urlRow(h.fixture.img2), findsOneWidget);
      expect(urlRow(h.fixture.song), findsOneWidget);
      // Models and PDFs are complete, so their groups disappear.
      expect(header('Models'), findsNothing);
      expect(header('PDFs'), findsNothing);
      expect(find.byType(AssetGroupHeader), findsNWidgets(3));
      // The chips still list every type.
      expect(chip('Models'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Missing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Downloaded'));
      await tester.pumpAndSettle();

      expect(urlRow(h.fixture.img1), findsOneWidget);
      expect(urlRow(h.fixture.img2), findsNothing);
      expect(find.byType(AssetUrlRow), findsNWidgets(3));
    });

    testWidgets('type chip narrows to one group and toggles back', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(chip('Models'));
      await tester.pumpAndSettle();

      expect(find.byType(AssetGroupHeader), findsOneWidget);
      expect(header('Models'), findsOneWidget);
      expect(find.byType(AssetUrlRow), findsOneWidget);
      expect(urlRow(h.fixture.model), findsOneWidget);
      expect(h.container.read(assetDetailFilterProvider).type, AssetType.model);

      await tester.tap(chip('Models'));
      await tester.pumpAndSettle();
      expect(find.byType(AssetGroupHeader), findsNWidgets(5));
      expect(h.container.read(assetDetailFilterProvider).type, isNull);
    });

    testWidgets('search narrows after the debounce and clears on mod switch', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byTooltip('Search URLs'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'IMG2');
      await tester.pump(assetSearchDebounce + const Duration(milliseconds: 20));
      await tester.pumpAndSettle();

      expect(find.byType(AssetUrlRow), findsOneWidget);
      expect(urlRow(h.fixture.img2), findsOneWidget);
      expect(find.byType(AssetGroupHeader), findsOneWidget);

      h.select(h.fixture.beta);
      await tester.pumpAndSettle();

      expect(h.container.read(assetDetailFilterProvider).query, '');
      expect(find.byType(TextField), findsNothing);
      expect(urlRow(h.fixture.b1), findsOneWidget);
    });

    testWidgets('Esc collapses the search and clears the query', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(find.byTooltip('Search URLs'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'model');
      await tester.pump(assetSearchDebounce + const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.byType(AssetUrlRow), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(h.container.read(assetDetailFilterProvider).query, '');
      expect(find.byType(AssetUrlRow), findsNWidgets(6));
    });

    testWidgets('invalid chip only with invalid URLs and filters to them', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      expect(chip('Invalid'), findsOneWidget);
      await tester.tap(chip('Invalid'));
      await tester.pumpAndSettle();

      expect(find.byType(AssetUrlRow), findsOneWidget);
      expect(urlRow(h.fixture.bundle), findsOneWidget);

      h.select(h.fixture.beta);
      await tester.pumpAndSettle();

      expect(chip('Invalid'), findsNothing);
      expect(h.container.read(assetDetailFilterProvider).invalidOnly, isFalse);
    });

    testWidgets('row colours follow state and selection', (tester) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);
      final context = tester.element(find.byType(SelectedModView));
      final colors = VaultColors.of(context);
      final scheme = Theme.of(context).colorScheme;

      expect(urlColor(tester, h.fixture.img1), colors.assetPresent);
      expect(urlColor(tester, h.fixture.img2), colors.assetMissing);
      expect(urlColor(tester, h.fixture.bundle), colors.assetInvalid);

      // Left click selects and opens the menu.
      await tester.tap(urlRow(h.fixture.img1));
      await tester.pumpAndSettle();
      expect(find.text('Copy URL'), findsOneWidget);
      await closeMenu(tester);

      expect(h.container.read(selectedAssetUrlProvider), h.fixture.img1.url);
      expect(urlColor(tester, h.fixture.img1), scheme.primary);

      // A second click on the selected row deselects without a menu.
      await tester.tap(urlRow(h.fixture.img1));
      await tester.pumpAndSettle();
      expect(find.text('Copy URL'), findsNothing);
      expect(h.container.read(selectedAssetUrlProvider), isNull);
      expect(urlColor(tester, h.fixture.img1), colors.assetPresent);
    });

    testWidgets('URL font size is applied, clamped and persisted', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);
      expect(
        tester.widget<Text>(find.text(h.fixture.img1.url)).style!.fontSize,
        AssetUrlFontSizeController.defaultSize,
      );

      await h.container.read(assetUrlFontSizeProvider.notifier).set(40);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.text(h.fixture.img1.url)).style!.fontSize,
        AssetUrlFontSizeController.maxSize,
      );
      expect(await h.store.read(AssetUrlFontSizeController.storageKey), '24.0');
    });

    testWidgets('header icons follow the group state', (tester) async {
      h.select(h.fixture.beta);
      await pumpPanel(tester, h);

      // Beta is complete: no download icon, but the images viewer button.
      expect(headerDownloadIcons, findsNothing);
      expect(find.byTooltip('View images'), findsOneWidget);

      h.select(h.fixture.alpha);
      await tester.pumpAndSettle();
      // Alpha misses images, audio and a bundle; the download icons are
      // wired in test/features/downloads/presentation.
      expect(find.byTooltip('Download all missing images'), findsOneWidget);
      expect(find.byTooltip('Download all missing audio'), findsOneWidget);
    });

    testWidgets('PDF header toggles thumbnails in the filter', (tester) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      expect(find.byTooltip('Show thumbnails'), findsOneWidget);
      // Switch to the Models chip first so the toggle does not have to
      // render a thumbnail from a file that does not exist.
      await tester.tap(chip('PDFs'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show thumbnails'));
      await tester.pump();

      expect(
        h.container.read(assetDetailFilterProvider).showPdfThumbnails,
        isTrue,
      );
      // Switch back to URLs before the delayed render would start.
      await tester.tap(find.byTooltip('Show URLs'));
      await tester.pumpAndSettle();
      expect(
        h.container.read(assetDetailFilterProvider).showPdfThumbnails,
        isFalse,
      );
      expect(urlRow(h.fixture.doc), findsOneWidget);
    });
  });

  group('toolbar audio', () {
    testWidgets('audio button only for mods with audio; menu sets it', (
      tester,
    ) async {
      h.select(h.fixture.beta);
      await pumpPanel(tester, h);
      expect(find.byType(AudioVisibilityButton), findsNothing);

      h.select(h.fixture.alpha);
      await tester.pumpAndSettle();
      expect(find.byType(AudioVisibilityButton), findsOneWidget);
      // Global default hides audio and Alpha follows it.
      expect(find.byTooltip('Using global setting (hidden)'), findsOneWidget);

      await tester.tap(find.byType(AudioVisibilityButton));
      await tester.pumpAndSettle();
      expect(find.text('Use global setting (hidden)'), findsOneWidget);
      await tester.tap(find.text('Always show'));
      await tester.pumpAndSettle();

      expect(h.library.resummarizeCalls, [h.fixture.alpha.jsonPath]);
      final stored = await h.db.libraryQueries.modSummary(
        h.fixture.alpha.jsonPath,
        ignoreAudioGlobally: true,
      );
      expect(stored?.audio, AudioVisibility.alwaysShow);
    });
  });

  group('context menu', () {
    testWidgets('right-click shows items for an existing vs a missing file', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await rightClick(tester, h.fixture.img1);
      expect(h.container.read(selectedAssetUrlProvider), h.fixture.img1.url);
      for (final label in [
        'Open URL in browser',
        'Copy URL',
        'Open file',
        'Open in file explorer',
        'Replace URL…',
        'Check URL',
        'Shared with…',
        'Delete file',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Download'), findsNothing);
      await closeMenu(tester);

      await rightClick(tester, h.fixture.img2);
      expect(h.container.read(selectedAssetUrlProvider), h.fixture.img2.url);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Open file'), findsNothing);
      expect(find.text('Open in file explorer'), findsNothing);
      expect(find.text('Delete file'), findsNothing);
      await closeMenu(tester);
    });

    testWidgets('Delete file asks first, then deletes through the service', (
      tester,
    ) async {
      final path = h.fixture.img1.path!;
      h.touch(path);
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await rightClick(tester, h.fixture.img1);
      await tester.tap(find.text('Delete file'));
      await tester.pumpAndSettle();

      expect(find.text('Delete asset file?'), findsOneWidget);
      // Beta references the same file key, so the body names it.
      expect(find.textContaining('shared with 1 mod'), findsOneWidget);
      expect(h.exists(path), isTrue);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.exists(path), isTrue);
      expect(h.library.assetFileChangeCalls, isEmpty);

      await rightClick(tester, h.fixture.img1);
      await tester.tap(find.text('Delete file'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(h.exists(path), isFalse);
      expect(h.library.assetFileChangeCalls, [
        {h.fixture.img1.fileKey},
      ]);
      expect(find.text('File deleted'), findsOneWidget);
    });

    testWidgets('Shared with lists the other mods or says not shared', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await rightClick(tester, h.fixture.img1);
      await tester.tap(find.text('Shared with…'));
      await tester.pumpAndSettle();

      expect(find.text('Shared asset'), findsOneWidget);
      expect(find.text('This asset is shared with 1 mod.'), findsOneWidget);
      expect(find.text('Mods'), findsOneWidget);
      expect(find.text('Beta Mod'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await rightClick(tester, h.fixture.model);
      await tester.tap(find.text('Shared with…'));
      await tester.pumpAndSettle();
      expect(
        find.text('This asset is not shared with other mods'),
        findsOneWidget,
      );
    });
  });

  group('replace URL dialog', () {
    const newUrl = 'https://cdn.example.net/replacement.png';

    String alphaJson(String url) =>
        '{"SaveName":"Alpha Mod","ObjectStates":[{"CustomImage":'
        '{"ImageURL":"$url"}}]}';

    Future<void> openDialog(WidgetTester tester) async {
      h.write(h.fixture.alpha.jsonPath, alphaJson(h.fixture.img1.url));
      h.touch(h.fixture.img1.path!);
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);
      await rightClick(tester, h.fixture.img1);
      await tester.tap(find.text('Replace URL…'));
      await tester.pumpAndSettle();
      expect(find.text('Replace URL'), findsOneWidget);
    }

    bool applyEnabled(WidgetTester tester) =>
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
            .onPressed !=
        null;

    testWidgets('validates: non-empty and different from the current URL', (
      tester,
    ) async {
      await openDialog(tester);

      // Prefilled with the current URL: nothing to apply, no error shown.
      expect(applyEnabled(tester), isFalse);
      expect(
        find.text('The new URL is the same as the current one'),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(find.text('Enter a URL'), findsOneWidget);
      expect(applyEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), h.fixture.img1.url);
      await tester.pumpAndSettle();
      expect(applyEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), newUrl);
      await tester.pumpAndSettle();
      expect(find.text('Enter a URL'), findsNothing);
      expect(applyEnabled(tester), isTrue);
      // The rename box is available and on for an existing file.
      final box = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(box.value, isTrue);
      expect(box.onChanged, isNotNull);
    });

    testWidgets('applies without renaming when the box is unchecked', (
      tester,
    ) async {
      await openDialog(tester);
      final oldPath = h.fixture.img1.path!;

      await tester.enterText(find.byType(TextField), newUrl);
      await tester.tap(find.text('Also rename the cached file'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Replace URL'), findsNothing);
      expect(find.text('URL replaced'), findsOneWidget);
      expect(
        h.fs.file(h.fixture.alpha.jsonPath).readAsStringSync(),
        alphaJson(newUrl),
      );
      expect(h.exists(oldPath), isTrue);
      expect(h.library.refreshModCalls, [h.fixture.alpha.jsonPath]);
      expect(h.container.read(selectedAssetUrlProvider), isNull);
    });

    testWidgets('applies and renames the cached file when checked', (
      tester,
    ) async {
      await openDialog(tester);
      final oldPath = h.fixture.img1.path!;
      final newPath = p.join(
        p.dirname(oldPath),
        '${fileNameFromUrl(newUrl)}${p.extension(oldPath)}',
      );

      await tester.enterText(find.byType(TextField), newUrl);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Replace URL'), findsNothing);
      expect(h.exists(oldPath), isFalse);
      expect(h.exists(newPath), isTrue);
      expect(h.library.assetFileChangeCalls, [
        {h.fixture.img1.fileKey, fileKeyFromUrl(newUrl)},
      ]);
    });

    testWidgets('rename box is disabled for a missing file', (tester) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);
      await rightClick(tester, h.fixture.img2);
      await tester.tap(find.text('Replace URL…'));
      await tester.pumpAndSettle();

      final box = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(box.value, isFalse);
      expect(box.onChanged, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Replace URL'), findsNothing);
    });
  });

  group('bottom bar', () {
    testWidgets('Download all follows the missing count; the other buttons '
        'are present', (tester) async {
      h.select(h.fixture.beta);
      await pumpPanel(tester, h);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Download all'),
            )
            .onPressed,
        isNull,
      );

      h.select(h.fixture.alpha);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Download all'),
            )
            .onPressed,
        isNotNull,
      );
      // Download all and Check URLs are wired in
      // test/features/downloads/presentation, Backup and Delete assets in
      // test/features/backups and test/features/cleanup.
      for (final label in [
        'Backup',
        'Check URLs',
        'Delete assets',
        'Update URLs',
      ]) {
        expect(find.widgetWithText(FilledButton, label), findsOneWidget);
      }
    });
  });
}
