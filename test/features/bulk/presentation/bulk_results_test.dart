// The bulk results dialogs on their own (sorting, summary counts, copy
// text) and the progress-bar label mapping of the bulk keys.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_failures_dialog.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_url_check_results_dialog.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart'
    show UrlCheckResult;
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations_en.dart';

import '../../library/presentation/presentation_test_harness.dart'
    show fixtureMod;

Future<void> pumpDialog(WidgetTester tester, Widget dialog) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = ThemeSettings.defaults();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(settings, Brightness.light),
      darkTheme: AppTheme.build(settings, Brightness.dark),
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: dialog),
    ),
  );
  await tester.pumpAndSettle();
}

UrlCheckResult check(
  List<String> invalid, {
  bool cancelled = false,
  List<String> unreachable = const [],
}) => UrlCheckResult(
  invalidUrls: invalid,
  unreachableDomains: unreachable,
  cancelled: cancelled,
  checked: 3,
  total: 3,
);

void main() {
  final alpha = fixtureMod('Alpha Mod', id: '1');
  final beta = fixtureMod('Beta Mod', id: '2');
  final gamma = fixtureMod('Gamma Mod', id: '3');
  final zeta = fixtureMod('Zeta Mod', id: '4');

  group('BulkUrlCheckResultsDialog', () {
    final result = BulkUrlCheckResult(
      outcomes: [
        BulkModOutcome(mod: alpha, value: check(const [])),
        BulkModOutcome(mod: zeta, value: check(const ['https://z/1'])),
        BulkModOutcome(
          mod: beta,
          value: check(const ['https://b/1', 'https://b/2']),
        ),
        BulkModOutcome(mod: gamma, error: 'timeout'),
      ],
      cancelled: false,
    );

    test('mods with invalid URLs come first, most invalid first', () {
      final mods = modsWithInvalidUrls(result);
      expect(mods.map((m) => m.$1.displayName), ['Beta Mod', 'Zeta Mod']);
      expect(
        bulkUrlCheckResultsText(mods),
        'Beta Mod\nhttps://b/1\nhttps://b/2\n\nZeta Mod\nhttps://z/1',
      );
    });

    testWidgets('summary, failed note, expandable sections', (tester) async {
      await pumpDialog(tester, BulkUrlCheckResultsDialog(result: result));

      expect(find.text('URL check complete'), findsOneWidget);
      expect(find.text('Mods with invalid URLs'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // mods with invalid
      expect(find.text('3'), findsWidgets); // invalid URLs, mods checked
      expect(find.text('1 mod could not be checked'), findsOneWidget);
      expect(find.text('Beta Mod (2)'), findsOneWidget);
      expect(find.text('Zeta Mod (1)'), findsOneWidget);
      expect(find.text('Alpha Mod'), findsNothing);
      expect(find.text('https://b/1'), findsNothing);

      await tester.tap(find.text('Beta Mod (2)'));
      await tester.pumpAndSettle();
      expect(find.text('https://b/1'), findsOneWidget);
      expect(find.text('https://b/2'), findsOneWidget);
      expect(find.text('Copy all invalid URLs'), findsOneWidget);
    });

    testWidgets('all valid and cancelled variants', (tester) async {
      await pumpDialog(
        tester,
        BulkUrlCheckResultsDialog(
          result: BulkUrlCheckResult(
            outcomes: [BulkModOutcome(mod: alpha, value: check(const []))],
            cancelled: true,
          ),
        ),
      );
      expect(find.text('URL check cancelled'), findsOneWidget);
      expect(find.text('All URLs are valid'), findsOneWidget);
      expect(find.text('Copy all invalid URLs'), findsNothing);
    });
  });

  group('BulkUrlCheckResultsDialog with unreachable domains', () {
    final result = BulkUrlCheckResult(
      outcomes: [
        BulkModOutcome(
          mod: alpha,
          value: check(const [], unreachable: const ['down.example']),
        ),
        BulkModOutcome(
          mod: beta,
          value: check(
            const ['https://b/1'],
            unreachable: const ['down.example', 'gone.example'],
          ),
        ),
      ],
      cancelled: false,
    );

    test('hosts are counted once; mods with only unreachable hosts are '
        'listed but not copied', () {
      expect(result.unreachableDomains, ['down.example', 'gone.example']);
      final mods = modsWithInvalidUrls(result);
      expect(mods.map((m) => m.$1.displayName), ['Beta Mod', 'Alpha Mod']);
      expect(bulkUrlCheckResultsText(mods), 'Beta Mod\nhttps://b/1');
    });

    testWidgets('title, summary tile and per-mod headings', (tester) async {
      await pumpDialog(tester, BulkUrlCheckResultsDialog(result: result));
      expect(
        find.text('URL check complete with unreachable domains'),
        findsOneWidget,
      );
      expect(find.text('Unreachable domains'), findsOneWidget);
      expect(find.text('Beta Mod (1 invalid, 2 unreachable)'), findsOneWidget);
      expect(find.text('Alpha Mod (0 invalid, 1 unreachable)'), findsOneWidget);

      await tester.tap(find.text('Alpha Mod (0 invalid, 1 unreachable)'));
      await tester.pumpAndSettle();
      expect(find.text('down.example'), findsOneWidget);
      expect(find.text('Unreachable domains'), findsNWidgets(2));
    });
  });

  group('BulkFailuresDialog', () {
    const failures = <BulkFailure>[
      (name: 'Beta Mod', detail: '1 file failed'),
      (name: 'Gamma Mod', detail: null),
    ];

    testWidgets('lists the failed mods with their detail', (tester) async {
      await pumpDialog(
        tester,
        const BulkFailuresDialog(
          title: 'Download',
          summary: 'Downloaded 3 files for 5 mods',
          failures: failures,
        ),
      );
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Downloaded 3 files for 5 mods'), findsOneWidget);
      expect(find.text('2 mods failed'), findsOneWidget);
      expect(find.text('Beta Mod'), findsOneWidget);
      expect(find.text('1 file failed'), findsOneWidget);
      expect(find.text('Gamma Mod'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    test('clipboard text', () {
      expect(
        bulkFailuresText('Download', 'Summary', failures),
        'Download\nSummary\n\nBeta Mod\n    1 file failed\nGamma Mod',
      );
    });
  });

  group('operationProgressText', () {
    final l10n = AppLocalizationsEn();

    OperationProgress progress(String label, {int done = 3, int total = 12}) =>
        OperationProgress(
          kind: OperationKind.bulk,
          label: label,
          done: done,
          total: total,
          detail: 'Some Mod',
        );

    test('maps the bulk and URL update keys', () {
      expect(
        operationProgressText(l10n, progress(OperationLabelKeys.bulkDownload)),
        'Downloading mods 3/12',
      );
      expect(
        operationProgressText(l10n, progress(OperationLabelKeys.bulkBackup)),
        'Backing up mods 3/12',
      );
      expect(
        operationProgressText(
          l10n,
          progress(OperationLabelKeys.bulkDownloadAndBackup),
        ),
        'Downloading and backing up mods 3/12',
      );
      expect(
        operationProgressText(
          l10n,
          progress(OperationLabelKeys.bulkDeleteAssets),
        ),
        'Deleting asset files for mods 3/12',
      );
      expect(
        operationProgressText(l10n, progress(OperationLabelKeys.bulkCheckUrls)),
        'Checking URLs for mods 3/12',
      );
      expect(
        operationProgressText(
          l10n,
          progress('urls.updating', done: 1, total: 4),
        ),
        'Updating URLs 1/4',
      );
      expect(
        operationProgressText(l10n, progress('bulk.download', total: 0)),
        'Downloading mods',
      );
    });
  });
}
