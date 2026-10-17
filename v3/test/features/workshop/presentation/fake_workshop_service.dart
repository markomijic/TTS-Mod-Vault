// A `WorkshopService` double: records every call and answers with
// configurable results, without touching the runner or Steam.

// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart';

/// Records calls and returns [downloadResult] / [updateResult].
final class FakeWorkshopService extends WorkshopService {
  FakeWorkshopService(super.ref);

  /// `(ids, targetDir)` pairs passed to `downloadByIds`.
  final List<(List<String>, String)> downloadByIdsCalls = [];

  /// `(mods, force)` pairs passed to `updateMods`.
  final List<(List<Mod>, bool)> updateModsCalls = [];

  /// Result of every `downloadByIds` call; by default every id succeeds.
  WorkshopDownloadBatchResult? downloadResult;

  /// Result of every `updateMods` call; by default every mod is updated.
  WorkshopUpdateBatchResult? updateResult;

  /// Whether calls throw as the runner does while something runs.
  bool alreadyRunning = false;

  void _guard() {
    if (alreadyRunning) throw StateError('An operation is already running');
  }

  @override
  Future<WorkshopDownloadBatchResult> downloadByIds(
    List<String> ids, {
    required String targetDir,
  }) async {
    _guard();
    downloadByIdsCalls.add((ids, targetDir));
    return downloadResult ??
        WorkshopDownloadBatchResult([
          for (final id in ids)
            WorkshopDownloadResult(
              id: id,
              status: WorkshopItemStatus.ok,
              title: 'Item $id',
              jsonPath: '$targetDir/$id.json',
            ),
        ]);
  }

  @override
  Future<WorkshopUpdateBatchResult> updateMods(
    List<Mod> mods, {
    bool force = false,
  }) async {
    _guard();
    updateModsCalls.add((mods, force));
    return updateResult ??
        WorkshopUpdateBatchResult([
          for (final mod in mods)
            WorkshopUpdateResult(
              id: mod.id,
              modName: mod.displayName,
              jsonPath: mod.jsonPath,
              status: WorkshopUpdateStatus.updated,
            ),
        ]);
  }
}

/// Overrides `workshopServiceProvider` with a [FakeWorkshopService]; read the
/// provider from the container and cast to reach the recorded calls.
Override fakeWorkshopServiceOverride() =>
    workshopServiceProvider.overrideWith(FakeWorkshopService.new);
