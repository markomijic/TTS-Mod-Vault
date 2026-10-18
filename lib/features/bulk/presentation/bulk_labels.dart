/// Localised names of the bulk dialogs' choices.
library;

import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart'
    show BulkBackupBehavior, DeleteAssetsScope, PostBackupDeletion;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Localised names of [BulkBackupBehavior].
extension BulkBackupBehaviorLabels on BulkBackupBehavior {
  /// Radio label ("Replace if out of date").
  String title(AppLocalizations l10n) => switch (this) {
    BulkBackupBehavior.skip => l10n.bulkBackupBehaviorSkip,
    BulkBackupBehavior.replace => l10n.bulkBackupBehaviorReplace,
    BulkBackupBehavior.replaceIfOutOfDate =>
      l10n.bulkBackupBehaviorReplaceIfOutOfDate,
  };
}

/// Localised names of [PostBackupDeletion].
extension PostBackupDeletionLabels on PostBackupDeletion {
  /// Radio label ("Keep the asset files").
  String title(AppLocalizations l10n) => switch (this) {
    PostBackupDeletion.none => l10n.postBackupKeep,
    PostBackupDeletion.deleteNonSharedAssets => l10n.postBackupDeleteNonShared,
    PostBackupDeletion.deleteAllAssets => l10n.postBackupDeleteAll,
  };
}

/// Localised names of [DeleteAssetsScope].
extension DeleteAssetsScopeLabels on DeleteAssetsScope {
  /// Radio label ("Delete shared files too").
  String title(AppLocalizations l10n) => switch (this) {
    DeleteAssetsScope.exclusiveOnly => l10n.deleteScopeExclusive,
    DeleteAssetsScope.all => l10n.deleteScopeAll,
  };
}
