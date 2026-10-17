/// Deleting the cached asset files of one mod (plan Phase 4): a scan that
/// splits the mod's files into exclusive and shared with other mods, and
/// the operation that deletes either set.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

/// Progress label while asset files are being deleted.
const deleteAssetsLabel = 'deleteAssets.deleting';

/// Which of a mod's cached files a delete covers.
enum DeleteAssetsScope {
  /// Only files no other mod references.
  exclusiveOnly,

  /// Every cached file of the mod, shared ones included.
  all,
}

/// What to do with a mod's cached files once it is backed up (the bulk
/// backup flows of Phase 5; v2 `PostBackupDeletionEnum`).
enum PostBackupDeletion {
  /// Keep every file.
  none,

  /// Delete the files no other mod references.
  deleteNonSharedAssets,

  /// Delete every cached file of the mod.
  deleteAllAssets;

  /// The delete scope this choice maps to, or null for [none].
  DeleteAssetsScope? get scope => switch (this) {
    PostBackupDeletion.none => null,
    PostBackupDeletion.deleteNonSharedAssets => DeleteAssetsScope.exclusiveOnly,
    PostBackupDeletion.deleteAllAssets => DeleteAssetsScope.all,
  };
}

/// Result of [DeleteAssetsService.scanModAssets].
///
/// [exclusive] are the mod's cached files no other mod references,
/// [shared] the ones at least one other mod uses; [sharedDetails] names
/// those mods per shared asset URL, grouped by type in `ModType.values`
/// order and sorted case-insensitively.
final class DeletableAssetsScan {
  /// Creates a scan result.
  const DeletableAssetsScan({
    required this.exclusive,
    required this.shared,
    required this.sharedDetails,
  });

  /// No cached files.
  static const DeletableAssetsScan empty = DeletableAssetsScan(
    exclusive: [],
    shared: [],
    sharedDetails: {},
  );

  /// Files only this mod references.
  final List<Asset> exclusive;

  /// Files other mods reference too.
  final List<Asset> shared;

  /// `url -> type -> display names` of the other mods sharing the file.
  final Map<String, Map<ModType, List<String>>> sharedDetails;

  /// Whether the mod has no cached files at all.
  bool get isEmpty => exclusive.isEmpty && shared.isEmpty;

  /// Number of other mods, saves and saved objects (counted per shared
  /// asset, like v2's `sharedWithMods` / `sharedWithSaves` /
  /// `sharedWithSavedObjects`).
  Map<ModType, int> get sharedWithCounts {
    final counts = {for (final type in ModType.values) type: 0};
    for (final byType in sharedDetails.values) {
      for (final entry in byType.entries) {
        counts[entry.key] = counts[entry.key]! + entry.value.length;
      }
    }
    return counts;
  }

  /// The assets a delete of [scope] covers.
  List<Asset> assetsFor(DeleteAssetsScope scope) => switch (scope) {
    DeleteAssetsScope.exclusiveOnly => exclusive,
    DeleteAssetsScope.all => [...exclusive, ...shared],
  };
}

/// Outcome of [DeleteModAssetsOperation].
final class DeleteAssetsResult {
  /// Creates a result.
  const DeleteAssetsResult({required this.deleted, required this.failed});

  /// Nothing deleted.
  static const DeleteAssetsResult empty = DeleteAssetsResult(
    deleted: 0,
    failed: 0,
  );

  /// Files deleted (a file that had already vanished counts as deleted,
  /// since the index is corrected either way).
  final int deleted;

  /// Files that could not be deleted.
  final int failed;

  @override
  String toString() => 'DeleteAssetsResult(deleted: $deleted, failed: $failed)';
}

/// The delete-assets facade.
final deleteAssetsServiceProvider = Provider<DeleteAssetsService>(
  DeleteAssetsService.new,
);

/// Scans and deletes the cached files of one mod. [deleteModAssets] throws
/// [StateError] when another operation is running. Not `final`, so widget
/// tests can substitute a fake.
class DeleteAssetsService {
  /// Creates the service on [ref].
  DeleteAssetsService(this.ref);

  /// Supplies the runner and the operations' collaborators.
  final Ref ref;

  /// Splits the cached files of [mod] (audio following its visibility and
  /// the global option) into exclusive and shared, with the sharing mods'
  /// names (v2 `scanForDeletableAssetsStatic`, on the index). Never
  /// throws: a store error is logged and yields [DeletableAssetsScan.empty].
  Future<DeletableAssetsScan> scanModAssets(Mod mod) async {
    try {
      return await scanDeletableAssets(ref, mod);
    } on Object catch (error, stackTrace) {
      ref
          .read(appLogProvider)
          .error(
            LogSource.cleanup,
            'Could not scan the asset files of "${mod.displayName}"',
            error: error,
            stackTrace: stackTrace,
            modPath: mod.jsonPath,
          );
      return DeletableAssetsScan.empty;
    }
  }

  /// Deletes the files of [mod] that [scope] covers. Pass the [scan] the
  /// user confirmed to avoid scanning twice.
  Future<DeleteAssetsResult> deleteModAssets(
    Mod mod, {
    required DeleteAssetsScope scope,
    DeletableAssetsScan? scan,
  }) => ref
      .read(operationRunnerProvider.notifier)
      .run(
        DeleteModAssetsOperation(ref: ref, mod: mod, scope: scope, scan: scan),
      );
}

/// The scan behind [DeleteAssetsService.scanModAssets]; throws on store
/// errors so operations can decide how to report them.
Future<DeletableAssetsScan> scanDeletableAssets(Ref ref, Mod mod) async {
  final db = ref.read(appDatabaseProvider);
  final ignoreAudio = ref.read(libraryOptionsProvider).ignoreAudioGlobally;
  final assets = await db.libraryQueries.assetsForMod(
    mod.jsonPath,
    includeAudio: !mod.audio.hideAudio(ignoreAudioGlobally: ignoreAudio),
  );
  final existing = [
    for (final asset in assets)
      if (asset.exists) asset,
  ];
  if (existing.isEmpty) return DeletableAssetsScan.empty;

  final counts = await db.libraryQueries.sharedUsageCounts({
    for (final asset in existing) asset.fileKey,
  });
  final exclusive = <Asset>[];
  final shared = <Asset>[];
  for (final asset in existing) {
    ((counts[asset.fileKey] ?? 1) > 1 ? shared : exclusive).add(asset);
  }

  final state = ref.read(libraryControllerProvider).value;
  final details = <String, Map<ModType, List<String>>>{};
  final namesByPath = <String, (ModType, String)?>{};
  for (final asset in shared) {
    final paths = await db.libraryQueries.modPathsReferencingFileKeys({
      asset.fileKey,
    }, excludeModPath: mod.jsonPath);
    final byType = <ModType, List<String>>{};
    for (final path in paths) {
      final named = namesByPath.putIfAbsent(path, () {
        final other = state?.modByPath(path);
        if (other != null) return (other.ref.type, other.displayName);
        return null;
      });
      if (named == null) continue;
      byType.putIfAbsent(named.$1, () => []).add(named.$2);
    }
    if (byType.isEmpty) continue;
    details[asset.url] = {
      for (final type in ModType.values)
        if (byType[type] case final list?)
          type: List.unmodifiable(
            list..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
          ),
    };
  }
  // Mods that are in the store but not (yet) in the state are named by
  // their file, so the dialog still shows that the file is shared.
  for (final asset in shared) {
    if (details.containsKey(asset.url)) continue;
    final paths = await db.libraryQueries.modPathsReferencingFileKeys({
      asset.fileKey,
    }, excludeModPath: mod.jsonPath);
    if (paths.isEmpty) continue;
    details[asset.url] = {
      ModType.mod: List.unmodifiable(
        [for (final path in paths) p.basename(path)]..sort(),
      ),
    };
  }
  return DeletableAssetsScan(
    exclusive: exclusive,
    shared: shared,
    sharedDetails: details,
  );
}

/// Deletes the cached files of [mod] that [scope] covers, drops their
/// `existing_files` rows, re-summarises every mod referencing them and
/// invalidates the asset list. Per-file failures are logged and counted;
/// the operation itself only fails when the scan does.
final class DeleteModAssetsOperation extends Operation<DeleteAssetsResult> {
  /// Creates the operation. [scan] is reused when given.
  DeleteModAssetsOperation({
    required this.ref,
    required this.mod,
    required this.scope,
    this.scan,
  });

  /// Supplies the database, file system and library.
  final Ref ref;

  /// The mod whose files are deleted.
  final Mod mod;

  /// Which files.
  final DeleteAssetsScope scope;

  /// A scan the caller already has, or null to scan now.
  final DeletableAssetsScan? scan;

  @override
  OperationKind get kind => OperationKind.deleteAssets;

  @override
  Future<DeleteAssetsResult> run(OperationContext ctx) async {
    final log = ctx.log;
    final db = ref.read(appDatabaseProvider);
    final fs = ref.read(fileSystemProvider);
    final DeletableAssetsScan resolved;
    try {
      resolved = scan ?? await scanDeletableAssets(ref, mod);
    } catch (error, stackTrace) {
      log.error(
        LogSource.cleanup,
        'Could not scan the asset files of "${mod.displayName}"',
        error: error,
        stackTrace: stackTrace,
        modPath: mod.jsonPath,
        operationId: ctx.operationId,
      );
      rethrow;
    }
    final targets = resolved.assetsFor(scope);
    if (targets.isEmpty) {
      log.info(
        LogSource.cleanup,
        'No asset files to delete for "${mod.displayName}"'
        '${scope == DeleteAssetsScope.exclusiveOnly && resolved.shared.isNotEmpty ? ': all ${resolved.shared.length} are shared with other mods' : ''}',
        modPath: mod.jsonPath,
        operationId: ctx.operationId,
      );
      return DeleteAssetsResult.empty;
    }

    var deleted = 0;
    var failed = 0;
    final keys = <String>{};
    for (var i = 0; i < targets.length; i++) {
      ctx.checkCancelled();
      final asset = targets[i];
      final path = asset.path;
      ctx.report(
        OperationProgress(
          kind: kind,
          label: deleteAssetsLabel,
          done: i,
          total: targets.length,
          detail: path == null ? asset.url : p.basename(path),
        ),
      );
      if (path == null) continue;
      try {
        await fs.deleteIfExists(path);
        await db.existingFilesDao.remove(asset.type, asset.fileKey);
        keys.add(asset.fileKey);
        deleted++;
      } catch (error, stackTrace) {
        failed++;
        log.error(
          LogSource.cleanup,
          'Could not delete cached file ${p.basename(path)}',
          error: error,
          stackTrace: stackTrace,
          modPath: mod.jsonPath,
          url: asset.url,
          operationId: ctx.operationId,
        );
      }
    }
    ctx.report(
      OperationProgress(
        kind: kind,
        label: deleteAssetsLabel,
        done: targets.length,
        total: targets.length,
      ),
    );
    if (ref.mounted) {
      final library = ref.read(libraryControllerProvider.notifier);
      await library.applyAssetFileChange(keys);
      await library.resummarizeMod(mod.jsonPath);
      if (ref.mounted) ref.invalidate(modAssetsProvider);
    }
    log.success(
      LogSource.cleanup,
      'Deleted $deleted asset file(s) of "${mod.displayName}"'
      '${failed == 0 ? '' : ', $failed failed'}'
      '${scope == DeleteAssetsScope.all ? ' (shared files included)' : ''}',
      modPath: mod.jsonPath,
      operationId: ctx.operationId,
    );
    return DeleteAssetsResult(deleted: deleted, failed: failed);
  }
}
