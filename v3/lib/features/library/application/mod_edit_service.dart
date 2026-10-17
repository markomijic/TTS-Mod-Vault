/// Per-mod edit operations of the Mods page and the selected-mod view
/// (plan section 6, Phase 2): rename, delete, save-as-mod, audio visibility,
/// replace an asset URL, delete a cached asset file, "shared with" lookup.
///
/// Every operation writes through the injected `FileSystem`, updates the
/// store, patches the library state through [LibraryController] and logs to
/// `AppLog` under [LogSource.library]. Failures come back as `Err`; nothing
/// is thrown to the UI.
library;

import 'package:file/file.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/result/result.dart';
import 'package:tts_mod_vault/data/db/app_database.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/parsing/mod_metadata.dart';
import 'package:tts_mod_vault/domain/rules/backup_rules.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';

/// The per-mod edit operations.
final modEditServiceProvider = Provider<ModEditService>(ModEditService.new);

/// Edits one mod at a time: its JSON file, its sibling image, its backup
/// archive and the cached asset files it references. See the library
/// comment for the contract shared by every method. Not `final`, so
/// widget tests can substitute a fake through [modEditServiceProvider].
class ModEditService {
  /// Creates the service on [_ref]; reads its collaborators lazily.
  ModEditService(this._ref);

  final Ref _ref;

  FileSystem get _fs => _ref.read(fileSystemProvider);
  AppDatabase get _db => _ref.read(appDatabaseProvider);
  AppLog get _log => _ref.read(appLogProvider);
  LibraryController get _library =>
      _ref.read(libraryControllerProvider.notifier);
  Mod? _modInState(String jsonPath) =>
      _ref.read(libraryControllerProvider).value?.modByPath(jsonPath);

  /// Renames [mod] by rewriting the `SaveName` value in its JSON (the file's
  /// creation time is preserved) and, with [renameBackup], renames its
  /// backup archive to the name the new save name produces, in whichever
  /// form (with or without the id) the existing backup used.
  ///
  /// Fails when the name is blank or the file has no `SaveName` (saved
  /// objects). A backup that cannot be renamed (source gone, target taken)
  /// is logged as a warning and left alone; the rename itself still
  /// succeeds. Returns the refreshed mod.
  Future<Result<Mod>> renameMod(
    Mod mod,
    String newSaveName, {
    bool renameBackup = false,
  }) async {
    final name = newSaveName.trim();
    if (name.isEmpty) {
      return _fail<Mod>('Name must not be empty', modPath: mod.jsonPath);
    }
    try {
      final file = _fs.file(mod.jsonPath);
      final text = await file.readAsString();
      if (extractSaveName(text) == null) {
        return _fail<Mod>(
          'The file has no SaveName to rename (saved objects cannot be '
          'renamed)',
          modPath: mod.jsonPath,
        );
      }
      await _fs.writeStringPreservingCreationTime(
        mod.jsonPath,
        replaceSaveName(text, name),
      );
      final stat = file.statSync();
      await _db.modsDao.rename(
        mod.jsonPath,
        saveName: name,
        mtimeMs: stat.modified.millisecondsSinceEpoch,
        sizeBytes: stat.size,
      );
      final backup = mod.backup;
      if (renameBackup && backup != null) {
        await _renameBackupFor(mod, backup, name);
      }
      await _library.refreshMod(mod.jsonPath);
      _log.success(
        LogSource.library,
        'Renamed "${mod.displayName}" to "$name"',
        modPath: mod.jsonPath,
      );
      return Ok(_modInState(mod.jsonPath) ?? mod.copyWith(saveName: name));
    } on Object catch (error, stackTrace) {
      return _failFrom<Mod>(
        'Could not rename "${mod.displayName}"',
        error,
        stackTrace,
        modPath: mod.jsonPath,
      );
    }
  }

  /// Renames [backup] on disk and in the store to the name [newSaveName]
  /// produces for [mod], keeping the "forced id" form when the current
  /// name used it (v2: forced when the name equals the forced candidate
  /// and differs from the standard one). Problems are logged, not thrown.
  Future<void> _renameBackupFor(
    Mod mod,
    Backup backup,
    String newSaveName,
  ) async {
    String nameFor(String saveName, {required bool forceIncludeId}) =>
        backupFileName(
          saveName: saveName,
          modId: mod.id,
          type: mod.ref.type,
          forceIncludeId: forceIncludeId,
        );
    final usedForce =
        backup.fileName == nameFor(mod.saveName, forceIncludeId: true) &&
        backup.fileName != nameFor(mod.saveName, forceIncludeId: false);
    final newFileName = nameFor(newSaveName, forceIncludeId: usedForce);
    if (newFileName == backup.fileName) return;

    final newPath = p.normalize(p.join(p.dirname(backup.path), newFileName));
    final source = _fs.file(backup.path);
    if (!source.existsSync()) {
      _log.warning(
        LogSource.library,
        'Backup not renamed: ${backup.fileName} is no longer on disk',
        modPath: mod.jsonPath,
      );
      return;
    }
    if (_fs.file(newPath).existsSync()) {
      _log.warning(
        LogSource.library,
        'Backup not renamed: a file named "$newFileName" already exists',
        details: newPath,
        modPath: mod.jsonPath,
      );
      return;
    }
    try {
      await source.rename(newPath);
    } on Object catch (error, stackTrace) {
      _log.error(
        LogSource.library,
        'Backup not renamed: could not rename ${backup.fileName}',
        error: error,
        stackTrace: stackTrace,
        modPath: mod.jsonPath,
      );
      return;
    }
    final renamed = backup.copyWith(
      path: newPath,
      fileName: newFileName,
      folder: p.basename(p.dirname(newPath)),
      matchingModPath: mod.jsonPath,
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
    _log.info(
      LogSource.library,
      'Renamed backup "${backup.fileName}" to "$newFileName"',
      modPath: mod.jsonPath,
    );
  }

  /// Deletes [mod]'s JSON and its sibling image (when it has one), drops its
  /// store rows and removes it from the library state and the selection.
  /// A backup matched to it stays on disk and loses its mod.
  Future<Result<void>> deleteMod(Mod mod) async {
    try {
      await _fs.deleteIfExists(mod.jsonPath);
      final imagePath = mod.imagePath;
      if (imagePath != null) await _fs.deleteIfExists(imagePath);
      await _db.modsDao.deleteByPaths([mod.jsonPath]);
      await _library.removeMod(mod.jsonPath);
      _log.success(
        LogSource.library,
        'Deleted "${mod.displayName}"',
        details: mod.jsonPath,
        modPath: mod.jsonPath,
      );
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      return _failFrom<void>(
        'Could not delete "${mod.displayName}"',
        error,
        stackTrace,
        modPath: mod.jsonPath,
      );
    }
  }

  /// Copies [save]'s JSON (and sibling image, best effort) into
  /// [targetFolder] as `<fileName>.json` (a typed `.json` is stripped),
  /// indexes the copy as a Workshop mod, selects it and returns it.
  ///
  /// Fails when the name is blank or a file with that name already exists in
  /// [targetFolder]; nothing is overwritten.
  Future<Result<Mod>> saveAsMod(
    Mod save, {
    required String targetFolder,
    required String fileName,
  }) async {
    final baseName = _stripJsonExtension(fileName.trim());
    if (baseName.isEmpty) {
      return _fail<Mod>(
        'Please enter a valid file name',
        modPath: save.jsonPath,
      );
    }
    final targetPath = p.normalize(p.join(targetFolder, '$baseName.json'));
    try {
      if (_fs.file(targetPath).existsSync() ||
          _fs.directory(targetPath).existsSync()) {
        return _fail<Mod>(
          'A file named "$baseName.json" already exists in the target folder',
          details: targetPath,
          modPath: save.jsonPath,
        );
      }
      await _fs.directory(targetFolder).create(recursive: true);
      await _fs.file(save.jsonPath).copy(targetPath);

      final imagePath = save.imagePath;
      if (imagePath != null && _fs.file(imagePath).existsSync()) {
        try {
          await _fs.file(imagePath).copy(p.join(targetFolder, '$baseName.png'));
        } on Object catch (error, stackTrace) {
          _log.warning(
            LogSource.library,
            'Saved as mod without its image: the image could not be copied',
            details: '$error\n$stackTrace',
            modPath: targetPath,
          );
        }
      }

      await _library.refreshMod(targetPath, type: ModType.mod);
      final mod = _modInState(targetPath);
      if (mod == null) {
        return _fail<Mod>(
          'The copy was written but could not be indexed; refresh the library',
          details: targetPath,
          modPath: save.jsonPath,
        );
      }
      if (_ref.mounted) {
        _ref.read(selectionProvider.notifier).select(targetPath);
      }
      _log.success(
        LogSource.library,
        'Saved "${save.displayName}" as mod $baseName.json',
        details: targetPath,
        modPath: targetPath,
      );
      return Ok(mod);
    } on Object catch (error, stackTrace) {
      return _failFrom<Mod>(
        'Could not save "${save.displayName}" as mod',
        error,
        stackTrace,
        modPath: save.jsonPath,
      );
    }
  }

  /// Sets [mod]'s audio visibility override and re-summarises it (no file
  /// read); the asset list provider is invalidated. Returns the updated mod.
  Future<Result<Mod>> setAudioVisibility(
    Mod mod,
    AudioVisibility visibility,
  ) async {
    try {
      await _db.modsDao.setAudioVisibility(mod.jsonPath, visibility);
      await _library.resummarizeMod(mod.jsonPath);
      _invalidateAssets(mod.jsonPath);
      _log.info(
        LogSource.library,
        'Audio visibility of "${mod.displayName}" set to ${visibility.name}',
        modPath: mod.jsonPath,
      );
      return Ok(_modInState(mod.jsonPath) ?? mod.copyWith(audio: visibility));
    } on Object catch (error, stackTrace) {
      return _failFrom<Mod>(
        'Could not change the audio visibility of "${mod.displayName}"',
        error,
        stackTrace,
        modPath: mod.jsonPath,
      );
    }
  }

  /// Replaces every occurrence of [asset]'s URL in [mod]'s JSON with
  /// [newUrl] (also matching the legacy Steam host form; creation time
  /// preserved) and, with [renameFile], renames the cached file to the name
  /// TTS gives the new URL, keeping its extension.
  ///
  /// Fails when the new URL is blank, when the old URL is not in the file,
  /// or when a file already occupies the new cached name (checked before
  /// anything is written). A cached file that is gone is skipped. Mods
  /// sharing the old or new file are re-summarised. Returns the refreshed
  /// mod.
  Future<Result<Mod>> replaceAssetUrl(
    Mod mod,
    Asset asset,
    String newUrl, {
    bool renameFile = false,
  }) async {
    final url = newUrl.trim();
    if (url.isEmpty) {
      return _fail<Mod>(
        'URL must not be empty',
        modPath: mod.jsonPath,
        url: asset.url,
      );
    }
    if (url == asset.url) return Ok(_modInState(mod.jsonPath) ?? mod);
    final oldKey = asset.fileKey;
    final newKey = fileKeyFromUrl(url);
    final sourcePath = asset.path;
    try {
      String? renameTarget;
      if (renameFile && sourcePath != null) {
        renameTarget = p.normalize(
          p.join(
            p.dirname(sourcePath),
            '${fileNameFromUrl(url)}${p.extension(sourcePath)}',
          ),
        );
        if (!p.equals(renameTarget, sourcePath) &&
            _fs.file(renameTarget).existsSync()) {
          return _fail<Mod>(
            'A cached file named "${p.basename(renameTarget)}" already exists',
            details: renameTarget,
            modPath: mod.jsonPath,
            url: asset.url,
          );
        }
      }

      final text = await _fs.file(mod.jsonPath).readAsString();
      final replaced = replaceUrl(text, asset.url, url);
      if (replaced == text) {
        return _fail<Mod>(
          'The URL was not found in the mod file',
          modPath: mod.jsonPath,
          url: asset.url,
        );
      }
      await _fs.writeStringPreservingCreationTime(mod.jsonPath, replaced);

      Failure? renameFailure;
      if (renameTarget != null && sourcePath != null) {
        try {
          final newPath = await _fs.renameKeepingExtension(
            sourcePath,
            fileNameFromUrl(url),
          );
          if (newPath == null) {
            _log.debugLog(
              LogSource.library,
              'Cached file not renamed: it is no longer on disk',
              details: sourcePath,
              modPath: mod.jsonPath,
              url: asset.url,
            );
          } else {
            await _db.existingFilesDao.remove(asset.type, oldKey);
            await _db.existingFilesDao.upsert(asset.type, newKey, newPath);
          }
        } on Object catch (error, stackTrace) {
          renameFailure = Failure(
            'The URL was replaced but the cached file could not be renamed',
            cause: error,
            stackTrace: stackTrace,
          );
          _log.error(
            LogSource.library,
            renameFailure.message,
            error: error,
            stackTrace: stackTrace,
            modPath: mod.jsonPath,
            url: asset.url,
          );
        }
      }

      await _library.refreshMod(mod.jsonPath);
      await _library.applyAssetFileChange({oldKey, newKey});
      _invalidateAssets(mod.jsonPath);
      if (renameFailure != null) return Err(renameFailure);
      _log.success(
        LogSource.library,
        'Replaced URL in "${mod.displayName}"'
        '${renameTarget == null ? '' : ' and renamed the cached file'}',
        details: '${asset.url} -> $url',
        modPath: mod.jsonPath,
        url: url,
      );
      return Ok(_modInState(mod.jsonPath) ?? mod);
    } on Object catch (error, stackTrace) {
      return _failFrom<Mod>(
        'Could not replace the URL in "${mod.displayName}"',
        error,
        stackTrace,
        modPath: mod.jsonPath,
        url: asset.url,
      );
    }
  }

  /// Deletes [asset]'s cached file, drops it from the `existing_files`
  /// index and re-summarises every mod referencing it. Fails when the asset
  /// has no cached file; a file that already vanished is still removed from
  /// the index.
  Future<Result<void>> deleteAssetFile(Mod mod, Asset asset) async {
    final path = asset.path;
    if (path == null) {
      return _fail<void>(
        'The asset has no cached file to delete',
        modPath: mod.jsonPath,
        url: asset.url,
      );
    }
    try {
      final deleted = await _fs.deleteIfExists(path);
      await _db.existingFilesDao.remove(asset.type, asset.fileKey);
      await _library.applyAssetFileChange({asset.fileKey});
      if (_ref.mounted) _ref.invalidate(modAssetsProvider);
      if (deleted) {
        _log.success(
          LogSource.library,
          'Deleted cached file ${p.basename(path)}',
          details: path,
          modPath: mod.jsonPath,
          url: asset.url,
        );
      } else {
        _log.warning(
          LogSource.library,
          'Cached file ${p.basename(path)} was already gone; index updated',
          details: path,
          modPath: mod.jsonPath,
          url: asset.url,
        );
      }
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      return _failFrom<void>(
        'Could not delete cached file ${p.basename(path)}',
        error,
        stackTrace,
        modPath: mod.jsonPath,
        url: asset.url,
      );
    }
  }

  /// Display names of the other mods that reference [asset]'s cached file
  /// (same `file_key`), grouped by type in [ModType.values] order and sorted
  /// case-insensitively; types without a sharing mod are absent. [mod]
  /// itself is excluded. Never throws: a store error yields an empty map
  /// and an error log entry.
  Future<Map<ModType, List<String>>> modsSharingAsset(
    Mod mod,
    Asset asset,
  ) async {
    try {
      final paths = await _db.libraryQueries.modPathsReferencingFileKeys({
        asset.fileKey,
      }, excludeModPath: mod.jsonPath);
      if (paths.isEmpty) return const {};
      final ignoreAudio = _ref.read(libraryOptionsProvider).ignoreAudioGlobally;
      final names = <ModType, List<String>>{};
      for (final path in paths) {
        final other =
            _modInState(path) ??
            await _db.libraryQueries.modSummary(
              path,
              ignoreAudioGlobally: ignoreAudio,
            );
        if (other == null) continue;
        names.putIfAbsent(other.ref.type, () => []).add(other.displayName);
      }
      return {
        for (final type in ModType.values)
          if (names[type] case final list?)
            type: List.unmodifiable(
              list..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
            ),
      };
    } on Object catch (error, stackTrace) {
      _log.error(
        LogSource.library,
        'Could not look up the mods sharing an asset',
        error: error,
        stackTrace: stackTrace,
        modPath: mod.jsonPath,
        url: asset.url,
      );
      return const {};
    }
  }

  // --- helpers -------------------------------------------------------------

  void _invalidateAssets(String jsonPath) {
    if (_ref.mounted) _ref.invalidate(modAssetsProvider(jsonPath));
  }

  /// A trailing `.json` (any case) removed from [fileName]; other dots are
  /// part of the name.
  static String _stripJsonExtension(String fileName) {
    const ext = '.json';
    return fileName.toLowerCase().endsWith(ext)
        ? fileName.substring(0, fileName.length - ext.length).trim()
        : fileName;
  }

  Result<T> _fail<T>(
    String message, {
    String? details,
    String? modPath,
    String? url,
  }) {
    _log.warning(
      LogSource.library,
      message,
      details: details,
      modPath: modPath,
      url: url,
    );
    return Err<T>(Failure(message));
  }

  Result<T> _failFrom<T>(
    String message,
    Object error,
    StackTrace stackTrace, {
    String? modPath,
    String? url,
  }) {
    _log.error(
      LogSource.library,
      message,
      error: error,
      stackTrace: stackTrace,
      modPath: modPath,
      url: url,
    );
    return Err<T>(
      Failure('$message: $error', cause: error, stackTrace: stackTrace),
    );
  }
}
