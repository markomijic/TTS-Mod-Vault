// DownloadResultsDialog and UrlCheckResultsDialog rendering, plus the
// plain-text forms used for the clipboard.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart';
import 'package:tts_mod_vault/features/downloads/presentation/download_results_dialog.dart';
import 'package:tts_mod_vault/features/downloads/presentation/url_check_results_dialog.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations_en.dart';

import '../../images_viewer/themed_app.dart';
import '../../library/presentation/presentation_test_harness.dart'
    show fixtureMod;

void main() {
  final l10n = AppLocalizationsEn();

  final mixed = DownloadBatchResult(const [
    DownloadOutcome(
      url: 'https://a.example/1.png',
      type: AssetType.image,
      status: DownloadStatus.downloaded,
      path: '1.png',
    ),
    DownloadOutcome(
      url: 'https://a.example/2.png',
      type: AssetType.image,
      status: DownloadStatus.failed,
      httpStatus: 503,
    ),
    DownloadOutcome(
      url: 'https://a.example/3.obj',
      type: AssetType.model,
      status: DownloadStatus.htmlErrorPage,
    ),
    DownloadOutcome(
      url: 'https://ignored.example/4.mp3',
      type: AssetType.audio,
      status: DownloadStatus.skippedIgnoredDomain,
    ),
    DownloadOutcome(
      url: 'https://a.example/5.pdf',
      type: AssetType.pdf,
      status: DownloadStatus.cancelled,
    ),
  ]);

  group('DownloadResultsDialog', () {
    testWidgets('renders the summary, the note and the failed rows', (
      tester,
    ) async {
      await pumpThemedApp(
        tester,
        home: Scaffold(body: DownloadResultsDialog(result: mixed)),
      );

      expect(find.text('Download results'), findsOneWidget);
      expect(
        find.text('Downloaded 1 of 5 files, 2 failed, 1 skipped, 1 cancelled'),
        findsOneWidget,
      );
      expect(
        find.text('The download was cancelled before every file was tried.'),
        findsOneWidget,
      );
      expect(find.text('Failed downloads'), findsOneWidget);
      expect(find.text('Images: https://a.example/2.png'), findsOneWidget);
      expect(find.text('HTTP 503'), findsOneWidget);
      expect(find.text('Models: https://a.example/3.obj'), findsOneWidget);
      expect(
        find.text('The server returned an HTML page instead of the file'),
        findsOneWidget,
      );
      // Downloaded, skipped and cancelled requests are not listed.
      expect(find.textContaining('1.png'), findsNothing);
      expect(find.textContaining('4.mp3'), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    test('plain text carries the same information', () {
      final text = downloadResultsText(l10n, mixed);
      expect(
        text,
        startsWith('Downloaded 1 of 5 files, 2 failed, 1 skipped, 1 cancelled'),
      );
      expect(text, contains('Failed downloads'));
      expect(text, contains('[Images] https://a.example/2.png\n    HTTP 503'));
      expect(text, contains('[Models] https://a.example/3.obj'));
      expect(
        downloadFailureText(
          l10n,
          const DownloadOutcome(
            url: 'u',
            type: AssetType.image,
            status: DownloadStatus.failed,
          ),
        ),
        'Download failed',
      );
    });
  });

  group('UrlCheckResultsDialog', () {
    final mod = fixtureMod('Alpha Mod', id: '100001');

    testWidgets('all valid', (tester) async {
      await pumpThemedApp(
        tester,
        home: Scaffold(
          body: UrlCheckResultsDialog(
            mod: mod,
            result: const UrlCheckResult(
              invalidUrls: [],
              cancelled: false,
              checked: 4,
              total: 4,
            ),
          ),
        ),
      );
      expect(find.text('Alpha Mod'), findsOneWidget);
      expect(find.text('All URLs are valid'), findsOneWidget);
      expect(find.text('Copy all invalid URLs'), findsNothing);
      expect(find.text('Re-check'), findsOneWidget);
    });

    testWidgets('lists the invalid URLs numbered', (tester) async {
      await pumpThemedApp(
        tester,
        home: Scaffold(
          body: UrlCheckResultsDialog(
            mod: mod,
            result: const UrlCheckResult(
              invalidUrls: ['https://x.example/a', 'https://x.example/b'],
              cancelled: false,
              checked: 4,
              total: 4,
            ),
          ),
        ),
      );
      expect(find.text('Invalid URLs: 2'), findsOneWidget);
      expect(find.text('1. '), findsOneWidget);
      expect(find.text('2. '), findsOneWidget);
      expect(find.text('https://x.example/a'), findsOneWidget);
      expect(find.text('Copy all invalid URLs'), findsOneWidget);
    });
  });
}
