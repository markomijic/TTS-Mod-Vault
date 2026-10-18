// The sidebar "Cleanup" flow: the scanning modal, the empty case, the
// confirmation dialog with preview and warnings, the delete call and the
// docked progress bar while the delete runs.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/shell/vault_sidebar.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/cleanup/application/cleanup_service.dart';
import 'package:tts_mod_vault/features/cleanup/presentation/cleanup_actions.dart';
import 'package:tts_mod_vault/features/cleanup/presentation/cleanup_confirm_dialog.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_progress_bar.dart';

import '../../backups/presentation/shell_test_harness.dart';
import '../../library/presentation/presentation_test_harness.dart';
import '../../operations/presentation/fake_operation_runner.dart';
import 'fake_cleanup_services.dart';

/// One mebibyte.
const int mib = 1024 * 1024;

void main() {
  late FixtureLibrary library;
  late ProviderContainer container;
  late FakeCleanupService service;

  setUpAll(() => library = FixtureLibrary.create());
  tearDownAll(() => library.delete());

  final String imagesDir = fixtureDirectories.assetDir(AssetType.image);
  final String modelsRaw = fixtureDirectories.rawAssetDir(AssetType.model)!;

  final candidates = [
    CleanupCandidate(
      path: p.join(imagesDir, 'httpexamplecomold.png'),
      type: AssetType.image,
      fileKey: 'httpexamplecomold',
      sizeBytes: mib,
      reason: CleanupReason.unreferenced,
      indexed: true,
    ),
    CleanupCandidate(
      path: p.join(imagesDir, 'httpcloud3steamusercontentcomugc1234.png'),
      type: AssetType.image,
      fileKey: 'httpcloud3steamusercontentcomugc1234',
      sizeBytes: mib ~/ 2,
      reason: CleanupReason.legacyDuplicate,
      indexed: true,
      twinPath: p.join(
        imagesDir,
        'httpssteamusercontent-aakamaihdnetugc1234.png',
      ),
    ),
    CleanupCandidate(
      path: p.join(modelsRaw, 'httpexamplecommesh.obj'),
      type: AssetType.model,
      fileKey: 'httpexamplecommesh',
      sizeBytes: mib,
      reason: CleanupReason.unreferenced,
      indexed: false,
    ),
  ];

  setUp(() {
    container = shellContainer(
      library.state,
      overrides: [cleanupServiceProvider.overrideWith(FakeCleanupService.new)],
    );
    service = container.read(cleanupServiceProvider) as FakeCleanupService;
  });

  testWidgets('an empty scan says so', (tester) async {
    await pumpShell(tester, container);

    await tapSidebar(tester, 'Cleanup');

    expect(service.scanCalls, 1);
    expect(find.byType(CleanupConfirmDialog), findsNothing);
    expect(find.text('No unused files found'), findsOneWidget);
    expect(service.deleteCalls, isEmpty);
  });

  testWidgets('a failed scan shows its warning instead', (tester) async {
    service.scan = const CleanupScan(
      candidates: [],
      warnings: ['Cleanup scan failed: boom'],
    );
    await pumpShell(tester, container);

    await tapSidebar(tester, 'Cleanup');

    expect(find.text('Cleanup scan failed: boom'), findsOneWidget);
  });

  testWidgets('the scanning modal shows while the scan runs and Cancel '
      'cancels the scan', (tester) async {
    final gate = Completer<void>();
    service
      ..gate = gate
      ..scan = CleanupScan(candidates: candidates, warnings: const []);
    await pumpShell(tester, container);

    await tester.tap(sidebarItem('Cleanup'));
    await tester.pump();
    expect(find.byType(ScanningDialog), findsOneWidget);
    expect(find.text('Scanning for unused files…'), findsOneWidget);
    expect(service.lastToken, isNotNull);
    expect(service.lastToken!.isCancelled, isFalse);

    // Dismiss: the token is cancelled and the aborted scan is swallowed.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.lastToken!.isCancelled, isTrue);
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ScanningDialog), findsNothing);
    expect(find.byType(CleanupConfirmDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(service.deleteCalls, isEmpty);
  });

  testWidgets('a scan that completes is not cancelled', (tester) async {
    await pumpShell(tester, container);

    await tapSidebar(tester, 'Cleanup');

    expect(service.lastToken, isNotNull);
    expect(service.lastToken!.isCancelled, isFalse);
  });

  testWidgets('the scanning modal closes itself when the scan answers', (
    tester,
  ) async {
    final gate = Completer<void>();
    service.gate = gate;
    await pumpShell(tester, container);

    await tester.tap(sidebarItem('Cleanup'));
    await tester.pump();
    expect(find.byType(ScanningDialog), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ScanningDialog), findsNothing);
    expect(find.text('No unused files found'), findsOneWidget);
  });

  group('with candidates', () {
    setUp(() {
      service.scan = CleanupScan(
        candidates: candidates,
        warnings: const ['Folder is missing: Audio'],
      );
    });

    testWidgets('the confirmation lists count, size, preview and warnings', (
      tester,
    ) async {
      await pumpShell(tester, container);

      await tapSidebar(tester, 'Cleanup');

      expect(find.byType(CleanupConfirmDialog), findsOneWidget);
      expect(find.text('Delete unused files?'), findsOneWidget);
      expect(
        find.text(
          '3 files (2.5 MB) are not used by any mod, save or saved object.',
        ),
        findsOneWidget,
      );
      expect(find.text('The files are deleted permanently.'), findsOneWidget);
      expect(find.text('Files (3)'), findsOneWidget);
      expect(find.text(candidates.first.path), findsNothing);

      await tester.tap(find.text('Files (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Images'), findsOneWidget);
      expect(find.text('Models'), findsOneWidget);
      for (final candidate in candidates) {
        expect(
          find.text(candidate.path),
          findsOneWidget,
          reason: candidate.path,
        );
      }
      expect(
        find.text(
          'legacy duplicate of httpssteamusercontent-aakamaihdnetugc1234.png',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Warnings (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Folder is missing: Audio'), findsOneWidget);
    });

    testWidgets('Cancel deletes nothing', (tester) async {
      await pumpShell(tester, container);

      await tapSidebar(tester, 'Cleanup');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(CleanupConfirmDialog), findsNothing);
      expect(service.deleteCalls, isEmpty);
    });

    testWidgets('Delete deletes every candidate and reports the size', (
      tester,
    ) async {
      await pumpShell(tester, container);

      await tapSidebar(tester, 'Cleanup');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(service.deleteCalls.single, same(candidates));
      expect(find.text('Deleted 3 files (2.5 MB)'), findsOneWidget);
    });

    testWidgets('failures are counted in the snack bar', (tester) async {
      service.deleteResult = const CleanupResult(
        deleted: 2,
        failed: 1,
        bytesFreed: 3 * mib ~/ 2,
      );
      await pumpShell(tester, container);

      await tapSidebar(tester, 'Cleanup');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Deleted 2 files (1.5 MB), 1 failed'), findsOneWidget);
    });

    testWidgets('a refused start shows the already-running snack bar', (
      tester,
    ) async {
      service.alreadyRunning = true;
      await pumpShell(tester, container);

      await tapSidebar(tester, 'Cleanup');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('An operation is already running'), findsOneWidget);
    });

    testWidgets('a large total is shown in GB', (tester) async {
      service.scan = CleanupScan(
        candidates: [
          CleanupCandidate(
            path: p.join(imagesDir, 'huge.png'),
            type: AssetType.image,
            fileKey: 'huge',
            sizeBytes: 1536 * mib,
            reason: CleanupReason.unreferenced,
            indexed: true,
          ),
        ],
        warnings: const [],
      );
      await pumpShell(tester, container);

      await tapSidebar(tester, 'Cleanup');

      expect(
        find.text(
          '1 file (1.50 GB) is not used by any mod, save or saved object.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('while the delete runs the bar is docked under the list and '
      'the sidebar is disabled', (tester) async {
    final running = shellContainer(
      library.state,
      overrides: [
        cleanupServiceProvider.overrideWith(FakeCleanupService.new),
        operationRunnerProvider.overrideWith(
          () => FakeOperationRunner(
            runningState(
              const OperationProgress(
                kind: OperationKind.cleanup,
                label: 'cleanup.deleting',
                done: 1,
                total: 4,
                detail: 'old.png',
              ),
            ),
          ),
        ),
      ],
    );
    await pumpShell(tester, running);

    expect(find.byType(OperationProgressBar), findsOneWidget);
    expect(find.text('Deleting unused files 1/4'), findsOneWidget);
    expect(find.text('old.png'), findsOneWidget);
    final cleanupItem = tester.widget<InkWell>(
      find.ancestor(
        of: find.descendant(
          of: find.byType(VaultSidebar),
          matching: find.byIcon(Icons.cleaning_services_outlined),
        ),
        matching: find.byType(InkWell),
      ),
    );
    expect(cleanupItem.onTap, isNull);
  });
}
