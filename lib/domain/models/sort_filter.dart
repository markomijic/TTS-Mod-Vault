import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tts_mod_vault/domain/enums/backup_status.dart';

part 'sort_filter.freezed.dart';

/// Sort orders for the mod library (same options as v2).
enum ModSortOption {
  /// Alphabetical by display name.
  nameAsc,

  /// Most recently saved first (by `epochTime`, then file mtime).
  newest,

  /// Most recently modified JSON first.
  recentlyUpdated,

  /// Mods with the most missing assets first.
  missingAssets,
}

/// Asset-based filters for the mod library.
enum AssetFilter {
  /// Every referenced asset is on disk.
  complete,

  /// At least one referenced asset is missing.
  missing,

  /// References at least one audio asset.
  audio,

  /// References at least one image.
  image,

  /// References at least one model.
  model,

  /// References at least one PDF.
  pdf,

  /// References at least one asset bundle.
  assetBundle,
}

/// Sort orders for the backups page.
enum BackupSortOption {
  nameAsc,
  nameDesc,
  sizeDesc,
  sizeAsc,
  dateDesc,
  dateAsc,
}

/// Whether a backup has a mod in the library that produces its file name.
enum BackupMatchFilter { hasMatchingMod, noMatchingMod }

/// Search, filter and sort state of the mod library.
///
/// Empty sets mean "no restriction". [isEmpty] ignores [sort]: sorting
/// never hides anything.
@freezed
abstract class ModFilter with _$ModFilter {
  const factory ModFilter({
    @Default('') String query,
    @Default(<String>{}) Set<String> folders,
    @Default(<BackupStatus>{}) Set<BackupStatus> backupStatuses,
    @Default(<AssetFilter>{}) Set<AssetFilter> assetFilters,
    @Default(ModSortOption.nameAsc) ModSortOption sort,
  }) = _ModFilter;

  const ModFilter._();

  /// No search text, no filters, default sort.
  static const ModFilter empty = ModFilter();

  /// Whether no search text or filter is active (sort is ignored).
  bool get isEmpty => query.trim().isEmpty && !hasFilters;

  /// True when any non-search filter (folders, backup states, asset filters)
  /// is active.
  bool get hasFilters =>
      folders.isNotEmpty ||
      backupStatuses.isNotEmpty ||
      assetFilters.isNotEmpty;

  /// Opposite of [isEmpty].
  bool get isNotEmpty => !isEmpty;
}
