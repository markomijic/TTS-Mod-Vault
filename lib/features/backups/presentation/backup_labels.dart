import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Localised names of [BackupSortOption].
extension BackupSortOptionLabels on BackupSortOption {
  /// Menu label.
  String label(AppLocalizations l10n) => switch (this) {
    BackupSortOption.nameAsc => l10n.backupSortNameAsc,
    BackupSortOption.nameDesc => l10n.backupSortNameDesc,
    BackupSortOption.sizeDesc => l10n.backupSortSizeDesc,
    BackupSortOption.sizeAsc => l10n.backupSortSizeAsc,
    BackupSortOption.dateDesc => l10n.backupSortDateDesc,
    BackupSortOption.dateAsc => l10n.backupSortDateAsc,
  };
}

/// Localised names of [BackupMatchFilter].
extension BackupMatchFilterLabels on BackupMatchFilter {
  /// Menu and badge label.
  String label(AppLocalizations l10n) => switch (this) {
    BackupMatchFilter.hasMatchingMod => l10n.backupMatchHasMod,
    BackupMatchFilter.noMatchingMod => l10n.backupMatchNoMod,
  };
}

/// Labels derived from a [Backup].
extension BackupLabels on Backup {
  /// "Has matching mod" / "No matching mod".
  String matchLabel(AppLocalizations l10n) => hasMatchingMod
      ? BackupMatchFilter.hasMatchingMod.label(l10n)
      : BackupMatchFilter.noMatchingMod.label(l10n);
}
