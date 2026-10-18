/// Filters of the selected-mod asset list and the grouped view model built
/// from them (plan section 6, Phase 2: "grouped asset list with
/// type/status/invalid/search filters").
library;

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';

/// Download-status filter of the asset list (v2 `ExistingAssetsFilter`).
enum AssetStatusFilter {
  /// Every asset.
  all,

  /// Only assets whose cached file is missing.
  missing,

  /// Only assets whose cached file is on disk.
  downloaded,
}

const Object _unset = Object();

/// What the asset list of the selected mod shows.
///
/// [type], [status], [invalidOnly] and [query] narrow the list;
/// [showPdfThumbnails] only changes how PDF assets are rendered and does
/// not count as a filter (see [isEmpty]).
final class AssetDetailFilter {
  /// Creates a filter; the defaults show everything as URLs.
  const AssetDetailFilter({
    this.type,
    this.status = AssetStatusFilter.all,
    this.invalidOnly = false,
    this.query = '',
    this.showPdfThumbnails = false,
  });

  /// No filter, URLs shown.
  static const AssetDetailFilter empty = AssetDetailFilter();

  /// Only assets of this type, or null for every type.
  final AssetType? type;

  /// Download-status filter.
  final AssetStatusFilter status;

  /// Only URLs a URL check flagged as dead.
  final bool invalidOnly;

  /// Case-insensitive substring the URL must contain (whitespace around it
  /// is ignored).
  final String query;

  /// Whether PDF assets are rendered as thumbnails instead of URLs.
  final bool showPdfThumbnails;

  /// The search text trimmed and lower-cased; empty when there is no search.
  String get normalizedQuery => query.trim().toLowerCase();

  /// Whether nothing narrows the list ([showPdfThumbnails] is not a filter).
  bool get isEmpty =>
      type == null &&
      status == AssetStatusFilter.all &&
      !invalidOnly &&
      normalizedQuery.isEmpty;

  /// Copy with some fields replaced; pass `type: null` to clear the type.
  AssetDetailFilter copyWith({
    Object? type = _unset,
    AssetStatusFilter? status,
    bool? invalidOnly,
    String? query,
    bool? showPdfThumbnails,
  }) => AssetDetailFilter(
    type: identical(type, _unset) ? this.type : type as AssetType?,
    status: status ?? this.status,
    invalidOnly: invalidOnly ?? this.invalidOnly,
    query: query ?? this.query,
    showPdfThumbnails: showPdfThumbnails ?? this.showPdfThumbnails,
  );

  /// Whether [asset] passes [type], [status], [invalidOnly] and [query].
  /// [invalidUrls] are the mod's flagged URLs; `asset.invalid` counts too.
  bool matches(Asset asset, {Set<String> invalidUrls = const {}}) {
    if (type != null && asset.type != type) return false;
    switch (status) {
      case AssetStatusFilter.all:
        break;
      case AssetStatusFilter.missing:
        if (asset.exists) return false;
      case AssetStatusFilter.downloaded:
        if (!asset.exists) return false;
    }
    if (invalidOnly && !asset.invalid && !invalidUrls.contains(asset.url)) {
      return false;
    }
    final needle = normalizedQuery;
    if (needle.isNotEmpty && !asset.url.toLowerCase().contains(needle)) {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is AssetDetailFilter &&
      other.type == type &&
      other.status == status &&
      other.invalidOnly == invalidOnly &&
      other.query == query &&
      other.showPdfThumbnails == showPdfThumbnails;

  @override
  int get hashCode =>
      Object.hash(type, status, invalidOnly, query, showPdfThumbnails);

  @override
  String toString() =>
      'AssetDetailFilter(type: $type, status: $status, '
      'invalidOnly: $invalidOnly, query: "$query", '
      'showPdfThumbnails: $showPdfThumbnails)';
}

/// Owns the [AssetDetailFilter] of the selected-mod view.
///
/// The presentation layer calls [reset] when the selected mod changes (v2
/// cleared type, invalid and search on selection); [showPdfThumbnails]
/// survives a reset because it is a view preference, not a filter. Its
/// initial value is the `showPdfThumbnails` setting; the filter starts over
/// when that setting changes.
final class AssetDetailFilterController extends Notifier<AssetDetailFilter> {
  @override
  AssetDetailFilter build() => AssetDetailFilter(
    showPdfThumbnails: ref.watch(showPdfThumbnailsSettingProvider),
  );

  /// Sets the type filter, or clears it when [type] is already selected or
  /// null (the chips toggle).
  void setType(AssetType? type) =>
      state = state.copyWith(type: state.type == type ? null : type);

  /// Sets the download-status filter.
  void setStatus(AssetStatusFilter status) =>
      state = state.copyWith(status: status);

  /// Shows only flagged URLs, or everything again.
  void setInvalidOnly(bool value) => state = state.copyWith(invalidOnly: value);

  /// Sets the search text.
  void setQuery(String query) => state = state.copyWith(query: query);

  /// Switches PDF assets between URLs and thumbnails.
  void setShowPdfThumbnails(bool value) =>
      state = state.copyWith(showPdfThumbnails: value);

  /// Clears every filter; [AssetDetailFilter.showPdfThumbnails] is kept.
  void reset() =>
      state = AssetDetailFilter(showPdfThumbnails: state.showPdfThumbnails);
}

/// The current [AssetDetailFilter].
final assetDetailFilterProvider =
    NotifierProvider<AssetDetailFilterController, AssetDetailFilter>(
      AssetDetailFilterController.new,
    );

/// One section of the grouped asset list: the assets of [type] that pass
/// the filter, plus the unfiltered totals for the section header.
final class AssetGroup {
  /// Creates a group.
  const AssetGroup({
    required this.type,
    required this.assets,
    required this.total,
    required this.missing,
  });

  /// The asset type of this section.
  final AssetType type;

  /// The assets of [type] passing the filter, in the store's URL order.
  final List<Asset> assets;

  /// Every asset of [type] the mod references, filtered or not.
  final int total;

  /// How many of [total] have no cached file.
  final int missing;

  /// How many of [total] are on disk.
  int get present => total - missing;

  /// Whether every asset of [type] is on disk.
  bool get isComplete => missing == 0;

  @override
  bool operator ==(Object other) =>
      other is AssetGroup &&
      other.type == type &&
      other.total == total &&
      other.missing == missing &&
      const ListEquality<Asset>().equals(other.assets, assets);

  @override
  int get hashCode => Object.hash(
    type,
    total,
    missing,
    const ListEquality<Asset>().hash(assets),
  );

  @override
  String toString() =>
      'AssetGroup($type, ${assets.length} shown of $total, $missing missing)';
}

/// Groups [assets] by type for the selected-mod view.
///
/// Returns one [AssetGroup] per [AssetType] the mod has at least one asset
/// of (filtered or not), in [AssetType.values] order; types the mod does
/// not reference are absent. Each group's [AssetGroup.assets] are the ones
/// passing [filter] (so a group can be empty while its totals are not),
/// and its totals count every asset of that type. [invalidUrls] are the
/// mod's URL-check flags, used by [AssetDetailFilter.invalidOnly] together
/// with `Asset.invalid`.
///
/// The presentation layer decides whether to show an empty group: v2 hid
/// the header of types other than the selected one and, while searching,
/// of types with no match.
List<AssetGroup> groupAssets(
  List<Asset> assets,
  AssetDetailFilter filter, {
  required Set<String> invalidUrls,
}) {
  if (assets.isEmpty) return const [];
  final shown = <AssetType, List<Asset>>{};
  final total = <AssetType, int>{};
  final missing = <AssetType, int>{};
  for (final asset in assets) {
    total.update(asset.type, (n) => n + 1, ifAbsent: () => 1);
    if (!asset.exists) {
      missing.update(asset.type, (n) => n + 1, ifAbsent: () => 1);
    }
    if (filter.matches(asset, invalidUrls: invalidUrls)) {
      shown.putIfAbsent(asset.type, () => []).add(asset);
    }
  }
  return [
    for (final type in AssetType.values)
      if (total.containsKey(type))
        AssetGroup(
          type: type,
          assets: List.unmodifiable(shown[type] ?? const <Asset>[]),
          total: total[type]!,
          missing: missing[type] ?? 0,
        ),
  ];
}

/// The grouped, filtered asset list of the mod at the given normalised JSON
/// path: [groupAssets] over [modAssetsProvider] and
/// [assetDetailFilterProvider], with the mod's `invalidUrls` from the
/// library state. Loading and error states pass through from the assets.
final groupedModAssetsProvider = Provider.autoDispose
    .family<AsyncValue<List<AssetGroup>>, String>((ref, jsonPath) {
      final filter = ref.watch(assetDetailFilterProvider);
      // The Mod is selected rather than its list: freezed gives it deep
      // equality, while a `List` compares by identity and would rebuild
      // on every unrelated patch.
      final mod = ref.watch(
        libraryControllerProvider.select((s) => s.value?.modByPath(jsonPath)),
      );
      final invalidUrls = mod?.invalidUrls ?? const <String>[];
      final invalid = invalidUrls.isEmpty
          ? const <String>{}
          : invalidUrls.toSet();
      return ref
          .watch(modAssetsProvider(jsonPath))
          .whenData(
            (assets) => groupAssets(assets, filter, invalidUrls: invalid),
          );
    });
