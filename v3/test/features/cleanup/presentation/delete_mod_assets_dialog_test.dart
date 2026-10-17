// The bottom bar "Delete assets" button: the scan-driven dialog (exclusive
// count, shared list, "also delete shared files") and the delete call.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/cleanup/application/delete_assets_service.dart';
import 'package:tts_mod_vault/features/cleanup/presentation/delete_mod_assets_dialog.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_progress_bar.dart';

import '../../asset_detail/presentation/asset_detail_test_harness.dart';
import '../../operations/presentation/fake_operation_runner.dart';
import 'fake_cleanup_services.dart';

void main() {
  late AssetDetailHarness h;
  late FakeDeleteAssetsService service;

  Future<void> setUpHarness({List<Override> extra = const []}) async {
    h = await AssetDetailHarness.create(
      overrides: [
        deleteAssetsServiceProvider.overrideWith(FakeDeleteAssetsService.new),
        ...extra,
      ],
    );
    service = h.container.read(
      deleteAssetsServiceProvider,
    ) as FakeDeleteAssetsService;
  }

  Finder button(String label) => find.widgetWithText(FilledButton, label);

  /// [matching] inside the dialog (the panel behind it lists the same
  /// URLs and type headings).
  Finder inDialog(Finder matching) => find.descendant(
    of: find.byType(DeleteModAssetsDialog),
    matching: matching,
  );

  Future<void> tapDeleteAssets(WidgetTester tester) async {
    h.select(h.fixture.alpha);
    await pumpPanel(tester, h);
    await tester.tap(button('Delete assets'));
    await tester.pumpAndSettle();
  }

  DeletableAssetsScan sharedScan() => DeletableAssetsScan(
    exclusive: [h.fixture.img1],
    shared: [h.fixture.model, h.fixture.doc],
    sharedDetails: {
      h.fixture.model.url: {
        ModType.mod: ['Beta Mod', 'Gamma Mod'],
        ModType.save: ['My Save'],
      },
      h.fixture.doc.url: {
        ModType.mod: ['Beta Mod'],
      },
    },
  );

  group('dialog', () {
    setUp(setUpHarness);

    testWidgets('a mod without cached files gets an informational snack bar', (
      tester,
    ) async {
      await tapDeleteAssets(tester);

      expect(service.scanCalls.single.jsonPath, h.fixture.alpha.jsonPath);
      expect(find.byType(DeleteModAssetsDialog), findsNothing);
      expect(find.text('No asset files to delete'), findsOneWidget);
      expect(service.deleteCalls, isEmpty);
    });

    testWidgets(
      'exclusive files only: no shared section, Delete deletes them',
      (tester) async {
        service.scan = DeletableAssetsScan(
          exclusive: [h.fixture.img1, h.fixture.model],
          shared: const [],
          sharedDetails: const {},
        );
        await tapDeleteAssets(tester);

        expect(find.byType(DeleteModAssetsDialog), findsOneWidget);
        expect(find.text('Delete asset files of Alpha Mod?'), findsOneWidget);
        expect(find.text('2 files are used only by this mod.'), findsOneWidget);
        expect(find.byType(Checkbox), findsNothing);
        expect(find.textContaining('shared with other mods'), findsNothing);
        expect(
          find.text(
            'The files are deleted permanently. The mod JSON file is not changed.',
          ),
          findsOneWidget,
        );

        await tester.tap(button('Delete'));
        await tester.pumpAndSettle();

        final (mod, scope, scan) = service.deleteCalls.single;
        expect(mod.jsonPath, h.fixture.alpha.jsonPath);
        expect(scope, DeleteAssetsScope.exclusiveOnly);
        expect(scan, same(service.scan));
        expect(find.text('Deleted 2 files'), findsOneWidget);
      },
    );

    testWidgets('shared files are listed with their mods; the checkbox widens '
        'the scope', (tester) async {
      service.scan = sharedScan();
      await tapDeleteAssets(tester);

      expect(find.text('1 file is used only by this mod.'), findsOneWidget);
      expect(
        find.text(
          '2 files are shared with other mods, saves or saved objects.',
        ),
        findsOneWidget,
      );
      expect(find.text('Also delete shared files (2)'), findsOneWidget);
      // The list is collapsed until expanded.
      expect(inDialog(find.text(h.fixture.model.url)), findsNothing);

      await tester.tap(find.text('Shared files (2)'));
      await tester.pumpAndSettle();

      expect(inDialog(find.text('Models')), findsOneWidget);
      expect(inDialog(find.text('PDFs')), findsOneWidget);
      expect(inDialog(find.text(h.fixture.model.url)), findsOneWidget);
      expect(
        find.text('Shared with Beta Mod, Gamma Mod (mods); My Save (saves)'),
        findsOneWidget,
      );
      expect(inDialog(find.text(h.fixture.doc.url)), findsOneWidget);
      expect(find.text('Shared with Beta Mod (mods)'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(button('Delete'));
      await tester.pumpAndSettle();

      final (_, scope, _) = service.deleteCalls.single;
      expect(scope, DeleteAssetsScope.all);
      expect(find.text('Deleted 3 files'), findsOneWidget);
    });

    testWidgets('without the checkbox only the exclusive files go', (
      tester,
    ) async {
      service.scan = sharedScan();
      await tapDeleteAssets(tester);

      await tester.tap(button('Delete'));
      await tester.pumpAndSettle();

      expect(service.deleteCalls.single.$2, DeleteAssetsScope.exclusiveOnly);
      expect(find.text('Deleted 1 file'), findsOneWidget);
    });

    testWidgets('all files shared: Delete is disabled until the checkbox', (
      tester,
    ) async {
      service.scan = DeletableAssetsScan(
        exclusive: const [],
        shared: [h.fixture.model],
        sharedDetails: {
          h.fixture.model.url: {
            ModType.mod: ['Beta Mod'],
          },
        },
      );
      await tapDeleteAssets(tester);

      expect(find.text('No file is used only by this mod.'), findsOneWidget);
      expect(tester.widget<FilledButton>(button('Delete')).enabled, isFalse);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button('Delete')).enabled, isTrue);
    });

    testWidgets('Cancel deletes nothing', (tester) async {
      service.scan = sharedScan();
      await tapDeleteAssets(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(DeleteModAssetsDialog), findsNothing);
      expect(service.deleteCalls, isEmpty);
    });

    testWidgets('failures are counted in the snack bar', (tester) async {
      service
        ..scan = sharedScan()
        ..deleteResult = const DeleteAssetsResult(deleted: 1, failed: 1);
      await tapDeleteAssets(tester);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(button('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Deleted 1 file, 1 failed'), findsOneWidget);
    });

    testWidgets('a refused start shows the already-running snack bar', (
      tester,
    ) async {
      service
        ..scan = sharedScan()
        ..alreadyRunning = true;
      await tapDeleteAssets(tester);

      await tester.tap(button('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('An operation is already running'), findsOneWidget);
    });
  });

  testWidgets('while the delete runs the bottom bar shows its progress', (
    tester,
  ) async {
    await setUpHarness(
      extra: [
        operationRunnerProvider.overrideWith(
          () => FakeOperationRunner(
            runningState(
              const OperationProgress(
                kind: OperationKind.deleteAssets,
                label: 'deleteAssets.deleting',
                done: 1,
                total: 3,
              ),
            ),
          ),
        ),
      ],
    );
    h.select(h.fixture.alpha);
    await pumpPanel(tester, h);

    expect(find.byType(OperationProgressBar), findsOneWidget);
    expect(find.text('Deleting asset files 1/3'), findsOneWidget);
    expect(button('Delete assets'), findsNothing);
  });
}
