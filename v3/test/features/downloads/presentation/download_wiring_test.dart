// The download and URL-check buttons of the selected-mod panel call the
// right `DownloadsService` methods and show the right result; the bottom
// bar swaps to the progress bar while an operation runs.

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_list.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_url_row.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_actions.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_actions.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_results_dialog.dart';
import 'package:tts_mod_vault/features/downloads/presentation/url_check_results_dialog.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_progress_bar.dart';

import '../../asset_detail/presentation/asset_detail_test_harness.dart';
import '../../operations/presentation/fake_operation_runner.dart';
import 'fake_downloads_service.dart';

void main() {
  late AssetDetailHarness h;
  late FakeDownloadsService service;
  var urlLive = false;

  Future<void> setUpHarness({List<Override> extra = const []}) async {
    h = await AssetDetailHarness.create(
      overrides: [
        fakeDownloadsServiceOverride(),
        singleUrlCheckProvider.overrideWithValue((url) async => urlLive),
        ...extra,
      ],
    );
    service =
        h.container.read(downloadsServiceProvider) as FakeDownloadsService;
  }

  setUp(() async {
    urlLive = false;
    await setUpHarness();
  });

  Finder button(String label) => find.widgetWithText(FilledButton, label);

  Future<void> rightClick(WidgetTester tester, Asset asset) async {
    await tester.tap(
      find.widgetWithText(AssetUrlRow, asset.url),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
  }

  group('downloads', () {
    testWidgets('Download all downloads the mod and reports the count', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(button('Download all'));
      await tester.pumpAndSettle();

      expect(service.downloadModCalls.map((m) => m.jsonPath), [
        h.fixture.alpha.jsonPath,
      ]);
      expect(find.text('Downloaded 1 file'), findsOneWidget);
      expect(find.byType(DownloadResultsDialog), findsNothing);
    });

    testWidgets('Download all is disabled when nothing is missing', (
      tester,
    ) async {
      h.select(h.fixture.beta);
      await pumpPanel(tester, h);
      expect(
        tester.widget<FilledButton>(button('Download all')).enabled,
        isFalse,
      );
    });

    testWidgets('header icon downloads the missing files of its type', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(find.byTooltip('Download all missing images'));
      await tester.pumpAndSettle();

      expect(service.downloadTypeCalls, hasLength(1));
      final (mod, type) = service.downloadTypeCalls.single;
      expect(mod.jsonPath, h.fixture.alpha.jsonPath);
      expect(type, AssetType.image);
    });

    testWidgets('asset menu Download downloads that asset', (tester) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await rightClick(tester, h.fixture.img2);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(service.downloadAssetCalls, hasLength(1));
      final (mod, asset) = service.downloadAssetCalls.single;
      expect(mod.jsonPath, h.fixture.alpha.jsonPath);
      expect(asset.url, h.fixture.img2.url);
    });

    testWidgets('a batch with failures shows the results dialog', (
      tester,
    ) async {
      service.downloadResult = DownloadBatchResult(const [
        DownloadOutcome(
          url: 'https://example.com/images/img2.png',
          type: AssetType.image,
          status: DownloadStatus.failed,
          httpStatus: 404,
          error: 'Not Found',
        ),
        DownloadOutcome(
          url: 'https://example.com/audio/song.mp3',
          type: AssetType.audio,
          status: DownloadStatus.downloaded,
          path: 'song.mp3',
        ),
      ]);
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(button('Download all'));
      await tester.pumpAndSettle();

      expect(find.byType(DownloadResultsDialog), findsOneWidget);
      expect(find.text('Download results'), findsOneWidget);
      expect(find.text('Downloaded 1 of 2 files, 1 failed'), findsOneWidget);
      expect(
        find.text('Images: https://example.com/images/img2.png'),
        findsOneWidget,
      );
      expect(find.text('HTTP 404 – Not Found'), findsOneWidget);
      expect(find.text('Downloaded 1 file'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadResultsDialog), findsNothing);
    });

    testWidgets('a refused start shows the already-running snack bar', (
      tester,
    ) async {
      service.alreadyRunning = true;
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(button('Download all'));
      await tester.pumpAndSettle();

      expect(find.text('An operation is already running'), findsOneWidget);
      expect(service.downloadModCalls, isEmpty);
    });
  });

  group('URL checks', () {
    testWidgets('Check URLs runs the check and shows all valid', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(button('Check URLs'));
      await tester.pumpAndSettle();

      expect(service.checkUrlsCalls.map((m) => m.jsonPath), [
        h.fixture.alpha.jsonPath,
      ]);
      expect(find.byType(UrlCheckResultsDialog), findsOneWidget);
      expect(find.text('All URLs are valid'), findsOneWidget);
      // The title is the mod name.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Alpha Mod'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('invalid URLs are listed with copy buttons', (tester) async {
      service.urlCheckResult = const UrlCheckResult(
        invalidUrls: ['https://dead.example/a.png', 'https://dead.example/b'],
        cancelled: false,
        checked: 6,
        total: 6,
      );
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(button('Check URLs'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid URLs: 2'), findsOneWidget);
      expect(find.text('https://dead.example/a.png'), findsOneWidget);
      expect(find.text('https://dead.example/b'), findsOneWidget);
      expect(find.text('Copy all invalid URLs'), findsOneWidget);
      expect(find.byTooltip('Copy URL'), findsNWidgets(2));
    });

    testWidgets('a cancelled check says so and shows the partial count', (
      tester,
    ) async {
      service.urlCheckResult = const UrlCheckResult(
        invalidUrls: [],
        cancelled: true,
        checked: 2,
        total: 6,
      );
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await tester.tap(button('Check URLs'));
      await tester.pumpAndSettle();

      expect(find.text('URL check cancelled'), findsOneWidget);
      expect(find.text('Checked 2 of 6 URLs'), findsOneWidget);
      expect(
        find.text('No invalid URLs found before cancelling'),
        findsOneWidget,
      );
    });

    testWidgets('Re-check runs the check again', (tester) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);
      await tester.tap(button('Check URLs'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Re-check'));
      await tester.pumpAndSettle();

      expect(service.checkUrlsCalls, hasLength(2));
      expect(find.byType(UrlCheckResultsDialog), findsOneWidget);
    });

    testWidgets('asset menu Check URL reports with a snack bar', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      await rightClick(tester, h.fixture.img1);
      await tester.tap(find.text('Check URL'));
      await tester.pumpAndSettle();
      expect(find.text('URL is not reachable'), findsOneWidget);

      urlLive = true;
      await rightClick(tester, h.fixture.img1);
      await tester.tap(find.text('Check URL'));
      await tester.pumpAndSettle();
      expect(find.text('URL is valid'), findsOneWidget);
    });
  });

  group('while an operation runs', () {
    setUp(() async {
      await setUpHarness(
        extra: [
          operationRunnerProvider.overrideWith(
            () => FakeOperationRunner(
              runningState(
                const OperationProgress(
                  kind: OperationKind.downloadAssets,
                  label: 'downloading.models',
                  done: 1,
                  total: 2,
                ),
              ),
            ),
          ),
        ],
      );
    });

    testWidgets('the bottom bar shows the progress bar instead of buttons', (
      tester,
    ) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      expect(find.byType(SelectedModActions), findsNothing);
      expect(find.byType(OperationProgressBar), findsOneWidget);
      expect(find.text('Downloading Models 1/2'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      expect(button('Download all'), findsNothing);
    });

    testWidgets('the header download icons are disabled', (tester) async {
      h.select(h.fixture.alpha);
      await pumpPanel(tester, h);

      final icon = find.descendant(
        of: find.byType(AssetGroupHeader),
        matching: find.byTooltip('Download all missing images'),
      );
      final iconButton = tester.widget<IconButton>(
        find.ancestor(of: icon, matching: find.byType(IconButton)),
      );
      expect(iconButton.onPressed, isNull);
    });
  });
}
