/// Facade the UI calls for everything backup-related: building the
/// operations of `backup_operations.dart` and handing them to the
/// `OperationRunner`, plus the two small file edits (delete, rename) that
/// need no progress bar.
library;

import 'package:collection/collection.dart' show IterableExtension;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/result/result.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/backup_rules.dart';
import 'package:tts_mod_vault/features/backups/application/backup_operations.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';

export 'package:tts_mod_vault/features/backups/application/backup_operations.dart'
    show
        BackupResult,
        ImportBackupsResult,
        ImportFileResult,
        ImportJsonResult,
        ImportResult,
        JsonConflictChoice,
        JsonConflictResolver,
        JsonImportConflict,
        backupWritingLabel,
        importExtractingLabel,
        importFileLabel;

/// The backups facade.
final backupServiceProvider = Provider<BackupService>(BackupService.new);

/// Where a backup of a mod would be written, and what it would affect.
///
/// The UI uses [currentBackupElsewhere] to ask "replace the existing backup
/// in its folder / write a new one here" before calling
/// [BackupService.createBackup] with the folder the user picked.
final class BackupTarget {
  /// Creates a target.
  const BackupTarget({
    required this.dir,
    required this.fileName,
    this.existingAtTarget,
    this.currentBackup,
  });

  /// Folder the archive would be written into.
  final String dir;

  /// Archive file name for the mod (honours the "force id" option).
  final String fileName;

  /// The archive already at [path] that would be overwritten, if any.
  final Backup? existingAtTarget;

  /// The backup currently matched to the mod, wherever it lives.
  final Backup? currentBackup;

  /// Full path of the archive.
  String get path => p.normalize(p.join(dir, fileName));

  /// Whether writing here overwrites an archive.
  bool get replacesExisting => existingAtTarget != null;

  /// Whether the mod's current backup lives in another folder than [dir]
  /// (writing here would leave two backups of the mod).
  bool get currentBackupElsewhere {
    final current = currentBackup;
    return current != null && !p.equals(current.path, path);
  }
}

/// Starts backup, import and import-JSON operations on the runner and
/// performs delete / rename of archives directly. The operation methods
/// throw [StateError] when another operation is running (the UI disables
/// the actions while `anyOperationRunningProvider` is true); the direct
/// edits come back as `Result`. Not `final`, so widget tests can substitute
/// a fake.
class BackupService {
  /// Creates the service on [ref].
  BackupService(this.ref);

  /// Supplies the runner and the operations' collaborators.
  final Ref ref;

  OperationRunner get _runner => ref.read(operationRunnerProvider.notifier);
  AppDatabase get _db => ref.read(appDatabaseProvider);
  AppLog get _log => ref.read(appLogProvider);
  LibraryController get _library =>
      ref.read(libraryControllerProvider.notifier);
  LibraryState? get _state => ref.read(libraryControllerProvider).value;

  /// Resolves where a backup of [mod] would go: [chosenDir] when given,
  /// else the folder of the mod's current backup, else the configured
  /// backups folder (empty when none is set; the UI must then ask).
  Future<BackupTarget> backupTargetFor(Mod mod, {String? chosenDir}) async {
    final directories = await ref.read(directoriesProvider.future);
    final options = await ref
        .read(libraryOptionsProvider.notifier)
        .ensureLoaded();
    final current = mod.backup;
    final dir =
        chosenDir ??
        (current != null ? p.dirname(current.path) : directories.backupsDir);
    final fileName = backupFileName(
      saveName: mod.saveName,
      modId: mod.id,
      type: mod.ref.type,
      forceIncludeId: options.forceBackupIdInName,
    );
    final path = p.normalize(p.join(dir, fileName));
    Backup? atTarget;
    for (final backup in _state?.backups ?? const <Backup>[]) {
      if (p.equals(backup.path, path)) {
        atTarget = backup;
        break;
      }
    }
    return BackupTarget(
      dir: dir,
      fileName: fileName,
      existingAtTarget: atTarget,
      currentBackup: current,
    );
  }

  /// Writes a backup of [mod] into [targetDir].
  Future<BackupResult> createBackup(Mod mod, {required String targetDir}) =>
      _runner.run(
        CreateBackupOperation(ref: ref, mod: mod, targetDir: targetDir),
      );

  /// Imports [paths] one after another; see `ImportBackupsOperation`.
  Future<ImportBackupsResult> importBackups(
    List<String> paths, {
    required JsonConflictResolver onJsonConflict,
    String? targetJsonDir,
  }) => _runner.run(
    ImportBackupsOperation(
      ref: ref,
      paths: paths,
      targetJsonDir: targetJsonDir,
      onJsonConflict: onJsonConflict,
    ),
  );

  /// Copies a JSON (+ optional PNG) into [destinationFolder] and indexes it.
  Future<ImportJsonResult> importJson({
    required String sourceJson,
    required String destinationFolder,
    required ModType type,
    String? sourcePng,
  }) => _runner.run(
    ImportJsonOperation(
      ref: ref,
      sourceJson: sourceJson,
      destinationFolder: destinationFolder,
      type: type,
      sourcePng: sourcePng,
    ),
  );

  /// Requests cancellation of the running operation.
  void cancel() => _runner.cancel();

  /// Deletes [backup] from disk, the store and the library state, and
  /// re-summarises the mod it was matched to so its status drops back to
  /// "no backup". An archive that already vanished is still unregistered.
  Future<Result<void>> deleteBackup(Backup backup) async {
    try {
      final deleted = await ref
          .read(fileSystemProvider)
          .deleteIfExists(backup.path);
      await _db.backupsDao.deleteByPaths([backup.path]);
      final modPath = _matchedModPath(backup);
      _library.removeBackup(backup.path);
      if (modPath != null) await _library.resummarizeMod(modPath);
      if (deleted) {
        _log.success(
          LogSource.backup,
          'Deleted backup ${backup.fileName}',
          details: backup.path,
          modPath: modPath,
        );
      } else {
        _log.warning(
          LogSource.backup,
          'Backup ${backup.fileName} was already gone; removed from the list',
          details: backup.path,
          modPath: modPath,
        );
      }
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      return _failFrom<void>(
        'Could not delete backup ${backup.fileName}',
        error,
        stackTrace,
        modPath: backup.matchingModPath,
      );
    }
  }

  /// Renames [backup] to [newFileName] in its folder (the `.ttsmod`
  /// extension is added when missing, invalid characters replaced) and
  /// updates the store and the library state. The mod it was matched to and
  /// any mod whose backup name the new name is are re-summarised.
  ///
  /// Fails when the name is blank, the archive is gone or another file
  /// already has the new name; nothing is overwritten.
  Future<Result<Backup>> renameBackup(Backup backup, String newFileName) async {
    var name = sanitizeFileName(newFileName);
    if (name.isEmpty ||
        name.toLowerCase() == ttsmodExtension ||
        p.basenameWithoutExtension(name).isEmpty) {
      return _fail<Backup>(
        'Backup name must not be empty',
        modPath: backup.matchingModPath,
      );
    }
    if (!name.toLowerCase().endsWith(ttsmodExtension)) {
      name = '$name$ttsmodExtension';
    }
    if (name == backup.fileName) return Ok(backup);
    final newPath = p.normalize(p.join(p.dirname(backup.path), name));
    final fs = ref.read(fileSystemProvider);
    try {
      final source = fs.file(backup.path);
      if (!source.existsSync()) {
        return _fail<Backup>(
          'Backup ${backup.fileName} is no longer on disk',
          details: backup.path,
          modPath: backup.matchingModPath,
        );
      }
      if (fs.file(newPath).existsSync() || fs.directory(newPath).existsSync()) {
        return _fail<Backup>(
          'A file named "$name" already exists in that folder',
          details: newPath,
          modPath: backup.matchingModPath,
        );
      }
      await source.rename(newPath);
      final previousModPath = _matchedModPath(backup);
      final renamed = backup.copyWith(
        path: newPath,
        fileName: name,
        folder: p.basename(p.dirname(newPath)),
        matchingModPath: null,
      );
      await _db.backupsDao.deleteByPaths([backup.path]);
      await _db.backupsDao.upsertAll([
        (
          path: newPath,
          mtimeMs: renamed.modified.millisecondsSinceEpoch,
          sizeBytes: renamed.sizeBytes,
          assetCount: renamed.assetCount,
        ),
      ]);
      _library.replaceBackup(backup.path, renamed);
      final toResummarize = <String>{?previousModPath, ..._modsProducing(name)};
      for (final modPath in toResummarize) {
        await _library.resummarizeMod(modPath);
      }
      _log.success(
        LogSource.backup,
        'Renamed backup "${backup.fileName}" to "$name"',
        details: newPath,
        modPath: previousModPath,
      );
      final current = _state?.backups
          .where((b) => b.path == newPath)
          .firstOrNull;
      return Ok(current ?? renamed);
    } on Object catch (error, stackTrace) {
      return _failFrom<Backup>(
        'Could not rename backup ${backup.fileName}',
        error,
        stackTrace,
        modPath: backup.matchingModPath,
      );
    }
  }

  /// The mod [backup] is matched to: its `matchingModPath`, else the mod in
  /// the state whose `backup` is this archive.
  String? _matchedModPath(Backup backup) {
    final direct = backup.matchingModPath;
    if (direct != null) return direct;
    for (final mod in _state?.all ?? const <Mod>[]) {
      if (mod.backup?.path == backup.path) return mod.jsonPath;
    }
    return null;
  }

  /// JSON paths of the mods whose backup file name is [fileName].
  Iterable<String> _modsProducing(String fileName) {
    final force = ref.read(libraryOptionsProvider).forceBackupIdInName;
    return [
      for (final mod in _state?.all ?? const <Mod>[])
        if (backupFileNameCandidates(
          ref: mod.ref,
          saveName: mod.saveName,
          forceIncludeId: force,
        ).contains(fileName))
          mod.jsonPath,
    ];
  }

  Result<T> _fail<T>(String message, {String? details, String? modPath}) {
    _log.warning(LogSource.backup, message, details: details, modPath: modPath);
    return Err<T>(Failure(message));
  }

  Result<T> _failFrom<T>(
    String message,
    Object error,
    StackTrace stackTrace, {
    String? modPath,
  }) {
    _log.error(
      LogSource.backup,
      message,
      error: error,
      stackTrace: stackTrace,
      modPath: modPath,
    );
    return Err<T>(
      Failure('$message: $error', cause: error, stackTrace: stackTrace),
    );
  }
}
