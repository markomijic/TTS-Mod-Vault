import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Localised names of [ModType].
extension ModTypeLabels on ModType {
  /// Capitalised plural, as shown on the type selector ("Mods").
  String title(AppLocalizations l10n) => switch (this) {
    ModType.mod => l10n.modTypeMods,
    ModType.save => l10n.modTypeSaves,
    ModType.savedObject => l10n.modTypeSavedObjects,
  };

  /// Lower-case singular noun for use inside sentences ("mod").
  String singular(AppLocalizations l10n) => switch (this) {
    ModType.mod => l10n.modTypeModSingular,
    ModType.save => l10n.modTypeSaveSingular,
    ModType.savedObject => l10n.modTypeSavedObjectSingular,
  };

  /// Lower-case plural noun for use inside sentences ("mods").
  String plural(AppLocalizations l10n) => switch (this) {
    ModType.mod => l10n.modTypeModPlural,
    ModType.save => l10n.modTypeSavePlural,
    ModType.savedObject => l10n.modTypeSavedObjectPlural,
  };

  /// "1 mod" / "12 mods".
  String count(AppLocalizations l10n, int count) =>
      l10n.countOfType(count, count == 1 ? singular(l10n) : plural(l10n));
}

/// Localised names of [ModSortOption].
extension ModSortOptionLabels on ModSortOption {
  /// Menu label.
  String label(AppLocalizations l10n) => switch (this) {
    ModSortOption.nameAsc => l10n.sortNameAsc,
    ModSortOption.newest => l10n.sortNewest,
    ModSortOption.recentlyUpdated => l10n.sortRecentlyUpdated,
    ModSortOption.missingAssets => l10n.sortMissingAssets,
  };
}

/// Localised names of [AssetFilter].
extension AssetFilterLabels on AssetFilter {
  /// Menu label.
  String label(AppLocalizations l10n) => switch (this) {
    AssetFilter.complete => l10n.assetFilterComplete,
    AssetFilter.missing => l10n.assetFilterMissing,
    AssetFilter.audio => l10n.assetFilterAudio,
    AssetFilter.image => l10n.assetFilterImage,
    AssetFilter.model => l10n.assetFilterModel,
    AssetFilter.pdf => l10n.assetFilterPdf,
    AssetFilter.assetBundle => l10n.assetFilterAssetBundle,
  };
}

/// Localised names of [BackupStatus].
extension BackupStatusLabels on BackupStatus {
  /// Menu and tooltip label.
  String label(AppLocalizations l10n) => switch (this) {
    BackupStatus.none => l10n.backupStatusNone,
    BackupStatus.upToDate => l10n.backupStatusUpToDate,
    BackupStatus.outOfDate => l10n.backupStatusOutOfDate,
    BackupStatus.assetCountMismatch => l10n.backupStatusAssetCountMismatch,
  };
}

/// Localised names of [AssetType].
extension AssetTypeLabels on AssetType {
  /// Plural label ("Images").
  String label(AppLocalizations l10n) => switch (this) {
    AssetType.assetBundle => l10n.assetTypeAssetBundles,
    AssetType.audio => l10n.assetTypeAudio,
    AssetType.image => l10n.assetTypeImages,
    AssetType.model => l10n.assetTypeModels,
    AssetType.pdf => l10n.assetTypePdfs,
  };
}

/// Localised names of [LibraryTab].
extension LibraryTabLabels on LibraryTab {
  /// Segment label ("Mods", "Backups").
  String title(AppLocalizations l10n) => switch (this) {
    LibraryTab.mods => ModType.mod.title(l10n),
    LibraryTab.saves => ModType.save.title(l10n),
    LibraryTab.savedObjects => ModType.savedObject.title(l10n),
    LibraryTab.backups => l10n.libraryTabBackups,
  };
}
