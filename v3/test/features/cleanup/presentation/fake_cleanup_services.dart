// `DeleteAssetsService` and `CleanupService` doubles: fixed scans,
// recorded delete calls, no runner and no disk.

// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'dart:async';

import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/cleanup/application/cleanup_service.dart';
import 'package:tts_mod_vault/features/cleanup/application/delete_assets_service.dart';

/// Serves [scan] and records `deleteModAssets` calls.
final class FakeDeleteAssetsService extends DeleteAssetsService {
  FakeDeleteAssetsService(super.ref);

  /// Answer of `scanModAssets`.
  DeletableAssetsScan scan = DeletableAssetsScan.empty;

  /// Mods passed to `scanModAssets`.
  final List<Mod> scanCalls = [];

  /// `(mod, scope, scan)` of every `deleteModAssets` call.
  final List<(Mod, DeleteAssetsScope, DeletableAssetsScan?)> deleteCalls = [];

  /// Answer of `deleteModAssets`, or computed from the scan when null.
  DeleteAssetsResult? deleteResult;

  /// Whether `deleteModAssets` throws as the runner does while busy.
  bool alreadyRunning = false;

  @override
  Future<DeletableAssetsScan> scanModAssets(Mod mod) async {
    scanCalls.add(mod);
    return scan;
  }

  @override
  Future<DeleteAssetsResult> deleteModAssets(
    Mod mod, {
    required DeleteAssetsScope scope,
    DeletableAssetsScan? scan,
  }) async {
    if (alreadyRunning) throw StateError('An operation is already running');
    deleteCalls.add((mod, scope, scan));
    return deleteResult ??
        DeleteAssetsResult(
          deleted: (scan ?? this.scan).assetsFor(scope).length,
          failed: 0,
        );
  }
}

/// Serves [scan] and records `deleteCandidates` calls.
final class FakeCleanupService extends CleanupService {
  FakeCleanupService(super.ref);

  /// Answer of `scanOrphans`.
  CleanupScan scan = const CleanupScan(candidates: [], warnings: []);

  /// How often `scanOrphans` was called.
  int scanCalls = 0;

  /// When set, `scanOrphans` waits for it before answering (lets a test
  /// observe the scanning modal).
  Completer<void>? gate;

  /// Candidate lists passed to `deleteCandidates`.
  final List<List<CleanupCandidate>> deleteCalls = [];

  /// Answer of `deleteCandidates`, or computed from the candidates.
  CleanupResult? deleteResult;

  /// Whether `deleteCandidates` throws as the runner does while busy.
  bool alreadyRunning = false;

  @override
  Future<CleanupScan> scanOrphans() async {
    scanCalls++;
    if (gate case final g?) await g.future;
    return scan;
  }

  @override
  Future<CleanupResult> deleteCandidates(
    List<CleanupCandidate> candidates,
  ) async {
    if (alreadyRunning) throw StateError('An operation is already running');
    deleteCalls.add(candidates);
    return deleteResult ??
        CleanupResult(
          deleted: candidates.length,
          failed: 0,
          bytesFreed: candidates.fold(0, (sum, c) => sum + c.sizeBytes),
        );
  }
}
