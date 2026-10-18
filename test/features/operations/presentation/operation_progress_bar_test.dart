// OperationProgressBar: label, determinate value, detail, Cancel and the
// idle behaviour, driven by a fake runner; plus the label-key mapping.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_labels.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_progress_bar.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations_en.dart';

import 'fake_operation_runner.dart';

void main() {
  final l10n = AppLocalizationsEn();

  OperationProgress progress({
    OperationKind kind = OperationKind.downloadAssets,
    String label = 'downloading.images',
    int done = 3,
    int total = 12,
    double? fraction,
    String? detail,
  }) => OperationProgress(
    kind: kind,
    label: label,
    done: done,
    total: total,
    fraction: fraction,
    detail: detail,
  );

  /// Pumps the bar for one frame: an indeterminate indicator animates
  /// forever, so `pumpAndSettle` would never return.
  Future<FakeOperationRunner> pumpBar(
    WidgetTester tester,
    OperationState state, {
    bool showWhenIdle = false,
  }) async {
    final runner = FakeOperationRunner(state);
    final settings = ThemeSettings.defaults();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationRunnerProvider.overrideWith(() => runner)],
        child: MaterialApp(
          theme: AppTheme.build(settings, Brightness.light),
          darkTheme: AppTheme.build(settings, Brightness.dark),
          themeMode: ThemeMode.dark,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: OperationProgressBar(showWhenIdle: showWhenIdle),
          ),
        ),
      ),
    );
    await tester.pump();
    return runner;
  }

  LinearProgressIndicator indicator(WidgetTester tester) =>
      tester.widget(find.byType(LinearProgressIndicator));

  group('OperationProgressBar', () {
    testWidgets('shows the label, the fraction, the detail and Cancel', (
      tester,
    ) async {
      await pumpBar(
        tester,
        runningState(progress(detail: 'https://example.com/a.png')),
      );

      expect(find.text('Downloading Images 3/12'), findsOneWidget);
      expect(find.text('https://example.com/a.png'), findsOneWidget);
      expect(indicator(tester).value, closeTo(0.25, 1e-9));
      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      expect(cancel, findsOneWidget);
      expect(tester.widget<OutlinedButton>(cancel).enabled, isTrue);
    });

    testWidgets('prefers the fraction and is indeterminate without a total', (
      tester,
    ) async {
      final runner = await pumpBar(
        tester,
        runningState(progress(done: 1, total: 4, fraction: 0.6)),
      );
      expect(indicator(tester).value, closeTo(0.6, 1e-9));

      runner.publish(
        runningState(progress(label: 'checking.urls', done: 0, total: 0)),
      );
      await tester.pump();
      expect(indicator(tester).value, isNull);
      expect(find.text('Checking URLs…'), findsOneWidget);
    });

    testWidgets('Cancel calls the runner and turns into Cancelling', (
      tester,
    ) async {
      final runner = await pumpBar(tester, runningState(progress()));

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(runner.cancelCalls, 1);
      expect(find.text('Cancel'), findsNothing);
      final cancelling = find.widgetWithText(OutlinedButton, 'Cancelling…');
      expect(cancelling, findsOneWidget);
      expect(tester.widget<OutlinedButton>(cancelling).enabled, isFalse);
      // Still shows the progress of the winding-down operation.
      expect(find.text('Downloading Images 3/12'), findsOneWidget);
    });

    testWidgets('collapses when idle, or shows the placeholder', (
      tester,
    ) async {
      await pumpBar(tester, OperationState.idle);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);

      await pumpBar(tester, OperationState.idle, showWhenIdle: true);
      expect(find.text('Operation in progress…'), findsOneWidget);
      expect(indicator(tester).value, isNull);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('a progress report without a label yet shows the generic '
        'text', (tester) async {
      await pumpBar(
        tester,
        const OperationState(
          operationId: 'x#1',
          kind: OperationKind.downloadAssets,
        ),
      );
      expect(find.text('Operation in progress…'), findsOneWidget);
      expect(indicator(tester).value, isNull);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('operationProgressText', () {
    test('maps the download label of every asset type', () {
      for (final type in AssetType.values) {
        final key = 'downloading.${type.folderName.toLowerCase()}';
        final text = operationProgressText(
          l10n,
          progress(label: key, done: 1, total: 2),
        );
        expect(text, startsWith('Downloading '), reason: key);
        expect(text, endsWith(' 1/2'), reason: key);
      }
      expect(
        operationProgressText(l10n, progress(label: 'downloading.pdf')),
        'Downloading PDFs 3/12',
      );
      expect(
        operationProgressText(
          l10n,
          progress(label: 'downloading.assetbundles', total: 0),
        ),
        'Downloading Asset bundles',
      );
    });

    test('maps the URL check and Workshop labels', () {
      expect(
        operationProgressText(
          l10n,
          progress(kind: OperationKind.checkUrls, label: 'checking.urls'),
        ),
        'Checked 3/12 URLs',
      );
      expect(
        operationProgressText(
          l10n,
          progress(
            kind: OperationKind.downloadWorkshop,
            label: 'workshop.downloading',
            done: 1,
            total: 3,
          ),
        ),
        'Downloading Workshop items 1/3',
      );
      expect(
        operationProgressText(
          l10n,
          progress(
            kind: OperationKind.updateWorkshop,
            label: 'workshop.updating',
            done: 0,
            total: 2,
          ),
        ),
        'Updating Workshop mods 0/2',
      );
      expect(
        operationProgressText(
          l10n,
          progress(
            kind: OperationKind.updateWorkshop,
            label: 'workshop.fetchingDetails',
          ),
        ),
        'Fetching Workshop item details…',
      );
    });

    test('maps the Phase 4 labels', () {
      expect(
        operationProgressText(
          l10n,
          progress(
            kind: OperationKind.backup,
            label: OperationLabelKeys.backupWriting,
            done: 1,
            total: 1,
          ),
        ),
        'Writing backup 1/1',
      );
      expect(
        operationProgressText(
          l10n,
          progress(
            kind: OperationKind.importBackup,
            label: OperationLabelKeys.importFile,
            done: 2,
            total: 5,
          ),
        ),
        'Importing backups 2/5',
      );
      expect(
        operationProgressText(
          l10n,
          progress(
            kind: OperationKind.importBackup,
            label: OperationLabelKeys.importExtracting,
            total: 0,
          ),
        ),
        'Extracting backup',
      );
      expect(
        operationProgressText(
          l10n,
          progress(
            kind: OperationKind.deleteAssets,
            label: OperationLabelKeys.deleteAssets,
            done: 4,
            total: 4,
          ),
        ),
        'Deleting asset files 4/4',
      );
      expect(
        operationProgressText(
          l10n,
          progress(
            kind: OperationKind.cleanup,
            label: OperationLabelKeys.cleanupDeleting,
            done: 0,
            total: 9,
          ),
        ),
        'Deleting unused files 0/9',
      );
    });

    test('humanises unknown keys instead of throwing', () {
      expect(
        operationProgressText(
          l10n,
          progress(label: 'something.newAndShiny', done: 2, total: 5),
        ),
        'Something new and shiny 2/5',
      );
      expect(
        operationProgressText(l10n, progress(label: 'downloading.wat')),
        'Downloading Wat 3/12',
      );
      expect(humanizeLabelKey('step_one-two'), 'Step one two');
      expect(humanizeLabelKey(''), '');
    });
  });
}
