/// Rewrites asset URL prefixes in one or more mod files and renames the
/// cached files to match (v2 `updateUrlPrefixes` /
/// `updateUrlPrefixesAllMods`), as an `Operation`.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_prefix_tasks.dart';

/// Progress label key while mod files are being rewritten.
const String updateUrlsProgressLabel = 'urls.updating';

/// Outcome of [UpdateUrlsOperation].
final class UpdateUrlsResult {
  /// Creates a result.
  const UpdateUrlsResult({
    required this.modsProcessed,
    required this.modsUpdated,
    required this.filesRenamed,
    required this.failed,
    required this.cancelled,
  });

  /// Mods the operation got to (every mod unless cancelled).
  final int modsProcessed;

  /// Mods whose file was rewritten.
  final int modsUpdated;

  /// Cached files renamed to the new URL's name.
  final int filesRenamed;

  /// Mods whose file could not be read or written, with the error text.
  final List<(String modPath, String error)> failed;

  /// Whether the run stopped early.
  final bool cancelled;

  @override
  String toString() =>
      'UpdateUrlsResult(processed: $modsProcessed, updated: $modsUpdated, '
      'renamed: $filesRenamed, failed: ${failed.length}'
      '${cancelled ? ', cancelled' : ''})';
}

/// For each of [mods]: reads the JSON on a worker, replaces the asset URLs
/// starting with any of [oldPrefixes] by their [newPrefix] form (see
/// `applyUrlPrefixes`), writes the file back preserving its creation time,
/// with [renameFiles] renames the cached files to the new URLs' names
/// (extension kept, `existing_files` updated), then re-indexes the mod.
///
/// A mod whose file cannot be processed is logged and counted in
/// `failed`; the run goes on. A cached file that cannot be renamed (target
/// taken) is logged as a warning and left alone. Cancellation is checked
/// between mods.
final class UpdateUrlsOperation extends Operation<UpdateUrlsResult> {
  /// Creates the operation.
  UpdateUrlsOperation({
    required this.ref,
    required this.mods,
    required this.oldPrefixes,
    required this.newPrefix,
    this.renameFiles = false,
  });

  /// Supplies the database, pool, file system and library.
  final Ref ref;

  /// The mods to rewrite.
  final List<Mod> mods;

  /// Prefixes to replace (already split and trimmed).
  final List<String> oldPrefixes;

  /// The replacement prefix.
  final String newPrefix;

  /// Whether cached files follow their URLs.
  final bool renameFiles;

  int _processed = 0;
  int _updated = 0;
  int _renamed = 0;
  final List<(String, String)> _failed = [];

  @override
  OperationKind get kind => OperationKind.updateUrls;

  @override
  UpdateUrlsResult? cancelledResult() => _result(cancelled: true);

  UpdateUrlsResult _result({required bool cancelled}) => UpdateUrlsResult(
    modsProcessed: _processed,
    modsUpdated: _updated,
    filesRenamed: _renamed,
    failed: List.unmodifiable(_failed),
    cancelled: cancelled,
  );

  @override
  Future<UpdateUrlsResult> run(OperationContext ctx) async {
    final log = ctx.log;
    final prefixes = [
      for (final prefix in oldPrefixes)
        if (prefix.trim().isNotEmpty) prefix.trim(),
    ];
    if (prefixes.isEmpty || newPrefix.trim().isEmpty) {
      log.warning(
        LogSource.library,
        'URL update skipped: old or new prefix is empty',
        operationId: ctx.operationId,
      );
      return _result(cancelled: false);
    }
    log.info(
      LogSource.library,
      'Updating URL prefixes in ${mods.length} mod(s): '
      '${prefixes.join(' | ')} -> $newPrefix'
      '${renameFiles ? ' (renaming cached files)' : ''}',
      operationId: ctx.operationId,
    );
    final total = mods.length;
    var cancelled = false;
    for (var i = 0; i < total; i++) {
      if (ctx.isCancelled) {
        cancelled = true;
        break;
      }
      final mod = mods[i];
      ctx.report(
        OperationProgress(
          kind: kind,
          label: updateUrlsProgressLabel,
          done: i,
          total: total,
          detail: mod.displayName,
        ),
      );
      try {
        await _updateMod(ctx, mod, prefixes);
      } on OperationCancelledException {
        cancelled = true;
        break;
      } on Object catch (error, stackTrace) {
        _failed.add((mod.jsonPath, error.toString()));
        log.error(
          LogSource.library,
          'Could not update URLs in "${mod.displayName}"',
          error: error,
          stackTrace: stackTrace,
          modPath: mod.jsonPath,
          operationId: ctx.operationId,
        );
      }
      _processed++;
    }
    ctx.report(
      OperationProgress(
        kind: kind,
        label: updateUrlsProgressLabel,
        done: _processed,
        total: total,
      ),
    );
    final result = _result(cancelled: cancelled);
    final message =
        'Updated URLs in $_updated of $total mod(s)'
        '${_renamed > 0 ? ', renamed $_renamed file(s)' : ''}'
        '${_failed.isNotEmpty ? ', ${_failed.length} failed' : ''}'
        '${cancelled ? ' (cancelled)' : ''}';
    if (_failed.isNotEmpty || cancelled) {
      log.warning(LogSource.library, message, operationId: ctx.operationId);
    } else {
      log.success(LogSource.library, message, operationId: ctx.operationId);
    }
    return result;
  }

  Future<void> _updateMod(
    OperationContext ctx,
    Mod mod,
    List<String> prefixes,
  ) async {
    final log = ctx.log;
    final db = ref.read(appDatabaseProvider);
    final assets = await db.libraryQueries.assetsForMod(mod.jsonPath);
    ctx.checkCancelled();
    final result = await ref
        .read(workerPoolProvider)
        .run(
          rewriteUrlPrefixesInFile,
          UrlPrefixFileRequest(
            jsonPath: mod.jsonPath,
            oldPrefixes: prefixes,
            newPrefix: newPrefix,
            assetUrls: [for (final asset in assets) asset.url],
          ),
          token: ctx.token,
        );
    if (!result.updated) {
      log.info(
        LogSource.library,
        'No URLs to update in "${mod.displayName}"',
        modPath: mod.jsonPath,
        operationId: ctx.operationId,
      );
      return;
    }
    _updated++;

    final changedKeys = <String>{};
    if (renameFiles) {
      final fs = ref.read(fileSystemProvider);
      final byUrl = {for (final asset in assets) asset.url: asset};
      for (final (oldUrl, newUrl) in result.renames) {
        final asset = byUrl[oldUrl];
        final path = asset?.path;
        if (asset == null || path == null) continue;
        final newKey = fileKeyFromUrl(newUrl);
        if (newKey == asset.fileKey) continue;
        try {
          final newPath = await fs.renameKeepingExtension(
            path,
            fileNameFromUrl(newUrl),
          );
          if (newPath == null) continue;
          await db.existingFilesDao.remove(asset.type, asset.fileKey);
          await db.existingFilesDao.upsert(asset.type, newKey, newPath);
          changedKeys
            ..add(asset.fileKey)
            ..add(newKey);
          _renamed++;
        } on Object catch (error, stackTrace) {
          log.warning(
            LogSource.library,
            'Cached file ${p.basename(path)} was not renamed',
            details: '$error\n$stackTrace',
            modPath: mod.jsonPath,
            url: oldUrl,
            operationId: ctx.operationId,
          );
        }
      }
    }

    if (!ref.mounted) return;
    final library = ref.read(libraryControllerProvider.notifier);
    await library.refreshMod(mod.jsonPath);
    if (changedKeys.isNotEmpty && ref.mounted) {
      await library.applyAssetFileChange(changedKeys);
    }
    if (ref.mounted) ref.invalidate(modAssetsProvider(mod.jsonPath));
    final changedUrls = result.renames.length;
    log.success(
      LogSource.library,
      'Updated URLs in "${mod.displayName}"'
      '${changedUrls == 0 ? '' : ': $changedUrls URL(s) changed'}',
      details: result.renames.isEmpty
          ? null
          : [for (final (a, b) in result.renames) '$a -> $b'].join('\n'),
      modPath: mod.jsonPath,
      operationId: ctx.operationId,
    );
  }
}
