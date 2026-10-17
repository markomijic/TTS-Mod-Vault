// A `BackupService` double: records every call and answers with
// configurable results, without touching the runner or the disk.

// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/result/result.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart';

import '../../library/presentation/presentation_test_harness.dart'
    show fixtureDirectories;

/// Records calls and returns configurable results. Set [alreadyRunning]
/// to make the operation methods throw the runner's [StateError].
final class FakeBackupService extends BackupService {
  FakeBackupService(super.ref);

  /// The configured backups folder `backupTargetFor` falls back to; empty
  /// means "no backups folder set".
  String backupsDir = fixtureDirectories.backupsDir;

  /// Archives that "exist" for the `existingAtTarget` check.
  List<Backup> existing = [];

  /// `(mod, chosenDir)` of every `backupTargetFor` call.
  final List<(Mod, String?)> targetCalls = [];

  /// `(mod, targetDir)` of every `createBackup` call.
  final List<(Mod, String)> createCalls = [];

  /// Error thrown by `createBackup` instead of answering, when set.
  Object? createError;

  /// `(paths, targetJsonDir)` of every `importBackups` call.
  final List<(List<String>, String?)> importCalls = [];

  /// When set, every imported archive raises this conflict and the answer
  /// is recorded in [conflictChoices].
  JsonImportConflict? conflict;

  /// Choices the conflict resolver returned.
  final List<JsonConflictChoice> conflictChoices = [];

  /// Per-path import override: an error message makes the archive fail.
  Map<String, String> importErrors = {};

  /// Paths left out of the result (as if the run was cancelled before).
  Set<String> notReached = {};

  /// Whether the import result reports a cancelled run.
  bool importCancelled = false;

  /// Arguments of every `importJson` call.
  final List<({String json, String folder, ModType type, String? png})>
  importJsonCalls = [];

  /// Backups passed to `deleteBackup`.
  final List<Backup> deleteCalls = [];

  /// Result of `deleteBackup`.
  Result<void> deleteResult = const Ok(null);

  /// `(backup, newName)` of every `renameBackup` call.
  final List<(Backup, String)> renameCalls = [];

  /// Failure returned by `renameBackup`, when set.
  Failure? renameFailure;

  /// Whether the operation methods throw as the runner does while
  /// something runs.
  bool alreadyRunning = false;

  void _guard() {
    if (alreadyRunning) throw StateError('An operation is already running');
  }

  /// The archive name the fake gives [mod].
  static String fileNameFor(Mod mod) => '${mod.displayName}.ttsmod';

  @override
  Future<BackupTarget> backupTargetFor(Mod mod, {String? chosenDir}) async {
    targetCalls.add((mod, chosenDir));
    final current = mod.backup;
    final dir =
        chosenDir ?? (current != null ? p.dirname(current.path) : backupsDir);
    final fileName = fileNameFor(mod);
    final path = p.normalize(p.join(dir, fileName));
    Backup? atTarget;
    for (final backup in existing) {
      if (p.equals(backup.path, path)) atTarget = backup;
    }
    return BackupTarget(
      dir: dir,
      fileName: fileName,
      existingAtTarget: atTarget,
      currentBackup: current,
    );
  }

  @override
  Future<BackupResult> createBackup(
    Mod mod, {
    required String targetDir,
  }) async {
    _guard();
    createCalls.add((mod, targetDir));
    if (createError case final error?) throw error;
    final fileName = fileNameFor(mod);
    return BackupResult(
      backup: Backup(
        path: p.normalize(p.join(targetDir, fileName)),
        fileName: fileName,
        folder: p.basename(targetDir),
        modified: DateTime(2024, 6),
        sizeBytes: 1024,
        assetCount: 3,
        matchingModPath: mod.jsonPath,
      ),
      assetCount: 3,
      skipped: 0,
    );
  }

  @override
  Future<ImportBackupsResult> importBackups(
    List<String> paths, {
    required JsonConflictResolver onJsonConflict,
    String? targetJsonDir,
  }) async {
    _guard();
    importCalls.add((paths, targetJsonDir));
    final results = <ImportFileResult>[];
    for (final path in paths) {
      if (notReached.contains(path)) continue;
      if (importErrors[path] case final error?) {
        results.add(ImportFileResult(path: path, error: error));
        continue;
      }
      var choice = JsonConflictChoice.useBackup;
      if (conflict case final c?) {
        choice = await onJsonConflict(c);
        conflictChoices.add(choice);
      }
      results.add(
        ImportFileResult(
          path: path,
          result: switch (choice) {
            JsonConflictChoice.cancel => const ImportResult(cancelled: true),
            JsonConflictChoice.keepCurrent => ImportResult(
              jsonPath: targetJsonDir,
              assetsExtracted: 3,
              jsonSkipped: true,
            ),
            JsonConflictChoice.useBackup => ImportResult(
              jsonPath: targetJsonDir,
              assetsExtracted: 3,
            ),
          },
        ),
      );
    }
    return ImportBackupsResult(results: results, cancelled: importCancelled);
  }

  @override
  Future<ImportJsonResult> importJson({
    required String sourceJson,
    required String destinationFolder,
    required ModType type,
    String? sourcePng,
  }) async {
    _guard();
    importJsonCalls.add((
      json: sourceJson,
      folder: destinationFolder,
      type: type,
      png: sourcePng,
    ));
    return ImportJsonResult(
      jsonPath: p.join(destinationFolder, p.basename(sourceJson)),
      imageCopied: sourcePng != null,
    );
  }

  @override
  Future<Result<void>> deleteBackup(Backup backup) async {
    deleteCalls.add(backup);
    return deleteResult;
  }

  @override
  Future<Result<Backup>> renameBackup(Backup backup, String newFileName) async {
    renameCalls.add((backup, newFileName));
    if (renameFailure case final failure?) return Err(failure);
    final name = newFileName.endsWith('.ttsmod')
        ? newFileName
        : '$newFileName.ttsmod';
    return Ok(
      backup.copyWith(
        path: p.join(p.dirname(backup.path), name),
        fileName: name,
      ),
    );
  }
}

/// Overrides `backupServiceProvider` with a [FakeBackupService]; read the
/// provider from the container and cast to reach the recorded calls.
Override fakeBackupServiceOverride() =>
    backupServiceProvider.overrideWith(FakeBackupService.new);
