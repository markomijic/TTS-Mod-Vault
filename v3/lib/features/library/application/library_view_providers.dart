import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';

/// Which of the three lists (mods, saves, saved objects) the page shows.
final class SelectedModTypeController extends Notifier<ModType> {
  @override
  ModType build() => ModType.mod;

  /// Switches the shown list.
  void set(ModType type) => state = type;
}

/// The [ModType] currently shown on the Mods page.
final selectedModTypeProvider =
    NotifierProvider<SelectedModTypeController, ModType>(
      SelectedModTypeController.new,
    );

/// Search text, filters and sort of the Mods page.
///
/// Folder filters are remembered per [ModType] (as in 2.x, where mods and
/// saves had separate folder sets): `state.folders` always holds the set of
/// the currently selected type, and switching the type swaps it.
final class ModFilterController extends Notifier<ModFilter> {
  final Map<ModType, Set<String>> _foldersByType = {};

  @override
  ModFilter build() {
    ref.listen(selectedModTypeProvider, (_, type) {
      state = state.copyWith(folders: _foldersFor(type));
    });
    return ModFilter.empty;
  }

  Set<String> _foldersFor(ModType type) =>
      Set.unmodifiable(_foldersByType[type] ?? const <String>{});

  /// Sets the search text.
  void setQuery(String query) => state = state.copyWith(query: query);

  /// Adds [folder] to the folder filter of the selected type, or removes it
  /// when present.
  void toggleFolder(String folder) {
    final type = ref.read(selectedModTypeProvider);
    final folders = _foldersByType.putIfAbsent(type, () => {});
    if (!folders.remove(folder)) folders.add(folder);
    state = state.copyWith(folders: _foldersFor(type));
  }

  /// Adds or removes a backup status from the filter.
  void toggleBackupStatus(BackupStatus status) {
    final statuses = Set<BackupStatus>.of(state.backupStatuses);
    if (!statuses.remove(status)) statuses.add(status);
    state = state.copyWith(backupStatuses: Set.unmodifiable(statuses));
  }

  /// Adds or removes an asset filter. [AssetFilter.missing] and
  /// [AssetFilter.complete] exclude each other: enabling one disables the
  /// other (2.x `addFilteredAssets`).
  void toggleAssetFilter(AssetFilter filter) {
    final filters = Set<AssetFilter>.of(state.assetFilters);
    if (!filters.remove(filter)) {
      if (filter == AssetFilter.missing) filters.remove(AssetFilter.complete);
      if (filter == AssetFilter.complete) filters.remove(AssetFilter.missing);
      filters.add(filter);
    }
    state = state.copyWith(assetFilters: Set.unmodifiable(filters));
  }

  /// Changes the sort order.
  void setSort(ModSortOption sort) => state = state.copyWith(sort: sort);

  /// Clears the search text and every filter for every type; the sort order
  /// is kept (2.x `resetState`).
  void clear() {
    _foldersByType.clear();
    state = ModFilter(sort: state.sort);
  }
}

/// The current [ModFilter] of the Mods page.
final modFilterProvider = NotifierProvider<ModFilterController, ModFilter>(
  ModFilterController.new,
);

/// Parent folder names of the mods of the selected type (the choices of the
/// folder filter), in alphabetical order.
final availableFoldersProvider = Provider<Set<String>>((ref) {
  final type = ref.watch(selectedModTypeProvider);
  final mods = ref.watch(
    libraryControllerProvider.select((s) => s.value?.byType(type)),
  );
  if (mods == null) return const {};
  final folders = {for (final mod in mods) mod.folder}.toList()..sort();
  return Set.unmodifiable(folders);
});

/// The mods of the selected type after search, filters and sort (port of
/// 2.x `filteredModsProvider`).
///
/// - search: `saveName` contains the query, case-insensitive;
/// - folders / backup statuses: the mod's value must be in the set;
/// - asset filters: `complete` requires every asset on disk, `missing` at
///   least one missing, `audio` any audio reference (even when audio is
///   hidden), the per-type filters at least one asset of that type;
/// - sort: [ModSortOption.nameAsc] by name; [ModSortOption.newest] by the
///   save time, falling back to the file mtime (2.x used the file's ctime,
///   which the index no longer keeps); [ModSortOption.recentlyUpdated] by
///   file mtime; [ModSortOption.missingAssets] by missing count. The three
///   non-name sorts break ties by name so the order is stable.
///
/// While a refresh runs the previous state is used, so the list never
/// flickers empty.
final filteredModsProvider = Provider<List<Mod>>((ref) {
  final type = ref.watch(selectedModTypeProvider);
  final filter = ref.watch(modFilterProvider);
  final mods = ref.watch(
    libraryControllerProvider.select((s) => s.value?.byType(type)),
  );
  if (mods == null) return const [];

  final query = filter.query.trim().toLowerCase();
  final filtered = [
    for (final mod in mods)
      if (_matches(mod, filter, query)) mod,
  ];
  filtered.sort(_comparatorFor(filter.sort));
  return filtered;
});

bool _matches(Mod mod, ModFilter filter, String query) {
  if (query.isNotEmpty && !mod.saveName.toLowerCase().contains(query)) {
    return false;
  }
  if (filter.folders.isNotEmpty && !filter.folders.contains(mod.folder)) {
    return false;
  }
  if (filter.backupStatuses.isNotEmpty &&
      !filter.backupStatuses.contains(mod.backupStatus)) {
    return false;
  }
  final assets = filter.assetFilters;
  if (assets.isEmpty) return true;
  final summary = mod.summary;
  if (assets.contains(AssetFilter.complete) && !summary.isComplete) {
    return false;
  }
  if (assets.contains(AssetFilter.missing) && summary.missing == 0) {
    return false;
  }
  if (assets.contains(AssetFilter.audio) && !summary.hasAudio) return false;
  if (assets.contains(AssetFilter.image) &&
      summary.totalOf(AssetType.image) == 0) {
    return false;
  }
  if (assets.contains(AssetFilter.model) &&
      summary.totalOf(AssetType.model) == 0) {
    return false;
  }
  if (assets.contains(AssetFilter.pdf) && summary.totalOf(AssetType.pdf) == 0) {
    return false;
  }
  if (assets.contains(AssetFilter.assetBundle) &&
      summary.totalOf(AssetType.assetBundle) == 0) {
    return false;
  }
  return true;
}

int _byName(Mod a, Mod b) =>
    a.saveName.toLowerCase().compareTo(b.saveName.toLowerCase());

/// Save time in milliseconds, or the file mtime when the JSON has no date.
int _newestKey(Mod mod) {
  final epoch = mod.epochTime;
  return epoch == null ? mod.modified.millisecondsSinceEpoch : epoch * 1000;
}

Comparator<Mod> _comparatorFor(ModSortOption sort) => switch (sort) {
  ModSortOption.nameAsc => _byName,
  ModSortOption.newest => (a, b) {
    final byTime = _newestKey(b).compareTo(_newestKey(a));
    return byTime != 0 ? byTime : _byName(a, b);
  },
  ModSortOption.recentlyUpdated => (a, b) {
    final byTime = b.modified.compareTo(a.modified);
    return byTime != 0 ? byTime : _byName(a, b);
  },
  ModSortOption.missingAssets => (a, b) {
    final byMissing = b.missingCount.compareTo(a.missingCount);
    return byMissing != 0 ? byMissing : _byName(a, b);
  },
};

/// The selected mods as a set of normalised JSON paths. One path means a
/// single selection (the detail view), several mean a bulk selection.
final class SelectionController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Selects exactly [jsonPath].
  void select(String jsonPath) => state = {jsonPath};

  /// Adds [jsonPath] to the selection, or removes it when selected
  /// (Ctrl-click).
  void toggle(String jsonPath) {
    final paths = Set<String>.of(state);
    if (!paths.remove(jsonPath)) paths.add(jsonPath);
    state = Set.unmodifiable(paths);
  }

  /// Replaces the selection with [jsonPaths].
  void selectMany(Iterable<String> jsonPaths) =>
      state = Set.unmodifiable(Set<String>.of(jsonPaths));

  /// Deselects everything.
  void clear() => state = const {};
}

/// The selected JSON paths.
final selectionProvider = NotifierProvider<SelectionController, Set<String>>(
  SelectionController.new,
);

/// The single selected mod, or null when none or several are selected or
/// the selected path is no longer in the library.
final selectedModProvider = Provider<Mod?>((ref) {
  final selection = ref.watch(selectionProvider);
  if (selection.length != 1) return null;
  final path = selection.single;
  return ref.watch(
    libraryControllerProvider.select((s) => s.value?.modByPath(path)),
  );
});

/// Every selected mod that is in the library, in selection order.
final selectedModsProvider = Provider<List<Mod>>((ref) {
  final selection = ref.watch(selectionProvider);
  if (selection.isEmpty) return const [];
  final library = ref.watch(libraryControllerProvider).value;
  if (library == null) return const [];
  return [for (final path in selection) ?library.modByPath(path)];
});
