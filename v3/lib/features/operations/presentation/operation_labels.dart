/// Maps the machine label keys operations report (plan section 4.5) to the
/// localised text of the progress bar.
library;

import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart'
    show checkUrlsProgressLabel;
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/features/operations/application/operation.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart'
    show
        workshopDetailsProgressLabel,
        workshopDownloadProgressLabel,
        workshopUpdateProgressLabel;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Prefix of the per-type download labels (`downloading.images`, ...).
const String downloadingLabelPrefix = 'downloading.';

/// Label keys the Phase 4 operations are expected to report. They are
/// mapped here so the bar reads well the moment those operations land; a
/// key that is not listed falls back to [humanizeLabelKey].
abstract final class OperationLabelKeys {
  /// Creating `.ttsmod` backups.
  static const String backupCreating = 'backup.creating';

  /// Importing `.ttsmod` backups.
  static const String backupImporting = 'backup.importing';

  /// Cleanup: scanning the asset folders for unused files.
  static const String cleanupScanning = 'cleanup.scanning';

  /// Cleanup: deleting unused files.
  static const String cleanupDeleting = 'cleanup.deleting';

  /// Deleting the cached files of a mod.
  static const String assetsDeleting = 'assets.deleting';

  /// Rewriting asset URLs in mod files.
  static const String urlsUpdating = 'urls.updating';
}

/// The text shown for [progress]: the label resolved from its key, with the
/// `done/total` count appended when the total is known.
///
/// `downloading.<type>` becomes "Downloading Images 3/12",
/// `checking.urls` becomes "Checked 3/12 URLs"; an unknown key is shown as
/// its humanised form so a new operation never crashes the bar.
String operationProgressText(AppLocalizations l10n, OperationProgress p) {
  final key = p.label;
  final hasTotal = p.total > 0;

  if (key == checkUrlsProgressLabel) {
    return hasTotal
        ? l10n.operationCheckedUrls(p.done, p.total)
        : l10n.operationCheckingUrls;
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
    OperationLabelKeys.backupCreating => l10n.operationBackupCreating,
    OperationLabelKeys.backupImporting => l10n.operationBackupImporting,
    OperationLabelKeys.cleanupScanning => l10n.operationCleanupScanning,
    OperationLabelKeys.cleanupDeleting => l10n.operationCleanupDeleting,
    OperationLabelKeys.assetsDeleting => l10n.operationAssetsDeleting,
    OperationLabelKeys.urlsUpdating => l10n.operationUrlsUpdating,
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
