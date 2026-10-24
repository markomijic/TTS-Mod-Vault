/// Maps the machine label keys operations report (plan section 4.5) to the
/// localised text of the progress bar.
library;

import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart'
    show checkDomainsProgressLabel, checkUrlsProgressLabel;
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';
import 'package:tts_mod_vault/features/url_updates/application/update_urls_operation.dart'
    show updateUrlsProgressLabel;
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart'
    show
        workshopDetailsProgressLabel,
        workshopDownloadProgressLabel,
        workshopUpdateProgressLabel;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Prefix of the per-type download labels (`downloading.images`, ...).
const String downloadingLabelPrefix = 'downloading.';

/// Label keys reported by the Phase 4 operations (`backup_operations.dart`,
/// `cleanup_service.dart`, `delete_assets_service.dart`), mirrored here as
/// literals so the bar does not depend on those libraries. A key that is
/// not listed falls back to [humanizeLabelKey].
abstract final class OperationLabelKeys {
  /// Writing a `.ttsmod` archive (`backupWritingLabel`; count = entries).
  static const String backupWriting = 'backup.writing';

  /// Extracting a `.ttsmod` archive (`importExtractingLabel`; count =
  /// entries).
  static const String importExtracting = 'import.extracting';

  /// A multi-file import (`importFileLabel`; count = files).
  static const String importFile = 'import.file';

  /// Cleanup deleting orphaned files (`cleanupDeletingLabel`).
  static const String cleanupDeleting = 'cleanup.deleting';

  /// Deleting a mod's cached files (`deleteAssetsLabel`).
  static const String deleteAssets = 'deleteAssets.deleting';

  /// Bulk download (`BulkDownloadOperation.progressLabel`; count = mods).
  static const String bulkDownload = 'bulk.download';

  /// Bulk backup (`BulkBackupOperation.progressLabel`; count = mods).
  static const String bulkBackup = 'bulk.backup';

  /// Bulk download then backup (`BulkDownloadAndBackupOperation`).
  static const String bulkDownloadAndBackup = 'bulk.downloadAndBackup';

  /// Bulk asset deletion (`BulkDeleteAssetsOperation`).
  static const String bulkDeleteAssets = 'bulk.deleteAssets';

  /// Bulk URL check (`BulkCheckUrlsOperation`).
  static const String bulkCheckUrls = 'bulk.checkUrls';

  /// URL prefix rewrite (`updateUrlsProgressLabel`; count = mods).
  static const String updateUrls = updateUrlsProgressLabel;
}

/// The text shown for [progress]: the label resolved from its key, with the
/// `done/total` count appended when the total is known.
///
/// `downloading.<type>` becomes "Downloading Images 3/12",
/// `checking.urls` becomes "Checked 3/12 URLs", `bulk.download` becomes
/// "Downloading mods 3/12" (the bar shows the current mod name from
/// `OperationProgress.detail` underneath); an unknown key is shown as
/// its humanised form so a new operation never crashes the bar.
String operationProgressText(AppLocalizations l10n, OperationProgress p) {
  final key = p.label;
  final hasTotal = p.total > 0;

  if (key == checkUrlsProgressLabel) {
    return hasTotal
        ? l10n.operationCheckedUrls(p.done, p.total)
        : l10n.operationCheckingUrls;
  }
  if (key == checkDomainsProgressLabel) {
    return hasTotal
        ? l10n.operationCheckedDomains(p.done, p.total)
        : l10n.operationCheckingDomains;
  }
  if (key == workshopDetailsProgressLabel) {
    return l10n.operationWorkshopFetchingDetails;
  }

  final base = _baseLabel(l10n, key);
  return hasTotal ? l10n.operationProgressCount(base, p.done, p.total) : base;
}

String _baseLabel(AppLocalizations l10n, String key) {
  if (key.startsWith(downloadingLabelPrefix)) {
    final suffix = key.substring(downloadingLabelPrefix.length);
    final type = assetTypeForLabelSuffix(suffix);
    return l10n.operationDownloading(
      type == null ? humanizeLabelKey(suffix) : type.label(l10n),
    );
  }
  return switch (key) {
    workshopDownloadProgressLabel => l10n.operationWorkshopDownloading,
    workshopUpdateProgressLabel => l10n.operationWorkshopUpdating,
    OperationLabelKeys.backupWriting => l10n.operationBackupWriting,
    OperationLabelKeys.importExtracting => l10n.operationImportExtracting,
    OperationLabelKeys.importFile => l10n.operationBackupImporting,
    OperationLabelKeys.cleanupDeleting => l10n.operationCleanupDeleting,
    OperationLabelKeys.deleteAssets => l10n.operationAssetsDeleting,
    OperationLabelKeys.bulkDownload => l10n.operationBulkDownloading,
    OperationLabelKeys.bulkBackup => l10n.operationBulkBackingUp,
    OperationLabelKeys.bulkDownloadAndBackup =>
      l10n.operationBulkDownloadingAndBackingUp,
    OperationLabelKeys.bulkDeleteAssets => l10n.operationBulkDeletingAssets,
    OperationLabelKeys.bulkCheckUrls => l10n.operationBulkCheckingUrls,
    OperationLabelKeys.updateUrls => l10n.operationUpdatingUrls,
    _ => humanizeLabelKey(key),
  };
}

/// The [AssetType] whose lower-cased folder name is [suffix]
/// (`images`, `assetbundles`, `audio`, `models`, `pdf`), or null.
AssetType? assetTypeForLabelSuffix(String suffix) {
  final wanted = suffix.toLowerCase();
  for (final type in AssetType.values) {
    if (type.folderName.toLowerCase() == wanted) return type;
  }
  return null;
}

/// "backup.creatingArchive" -> "Backup creating archive": dots become
/// spaces, camel-case humps are split, and the first letter is capitalised.
String humanizeLabelKey(String key) {
  final words = key
      .split(RegExp(r'[._\-]+'))
      .where((part) => part.isNotEmpty)
      .expand(
        (part) => part
            .replaceAllMapped(
              RegExp('([a-z0-9])([A-Z])'),
              (m) => '${m[1]} ${m[2]}',
            )
            .split(' '),
      )
      .map((word) => word.toLowerCase())
      .toList();
  if (words.isEmpty) return key;
  final first = words.first;
  words[0] = first[0].toUpperCase() + first.substring(1);
  return words.join(' ');
}
