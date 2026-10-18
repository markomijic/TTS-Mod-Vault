import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';

/// Search text, filters and sort of the Backups tab.
///
/// Empty sets mean "no restriction". [isEmpty] ignores [sort]: sorting
/// never hides anything.
@immutable
final class BackupFilter {
  /// Creates a filter.
  const BackupFilter({
    this.query = '',
    this.folders = const <String>{},
    this.match = const <BackupMatchFilter>{},
    this.sort = BackupSortOption.nameAsc,
  });

  /// No search text, no filters, default sort.
  static const BackupFilter empty = BackupFilter();

  /// Search text; matched against the file name, case-insensitive.
  final String query;

  /// Parent folder names the backup must be in (empty: any).
  final Set<String> folders;

  /// Whether the backup must have, or must not have, a matching mod. Both
  /// values together match everything, as in 2.x.
  final Set<BackupMatchFilter> match;

  /// Sort order.
  final BackupSortOption sort;

  /// Whether no search text or filter is active (sort is ignored).
  bool get isEmpty => query.trim().isEmpty && !hasFilters;

  /// Opposite of [isEmpty].
  bool get isNotEmpty => !isEmpty;

  /// True when any non-search filter (folders, match) is active.
  bool get hasFilters => folders.isNotEmpty || match.isNotEmpty;

  /// Copy with some fields replaced.
  BackupFilter copyWith({
    String? query,
    Set<String>? folders,
    Set<BackupMatchFilter>? match,
    BackupSortOption? sort,
  }) => BackupFilter(
    query: query ?? this.query,
    folders: folders ?? this.folders,
    match: match ?? this.match,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is BackupFilter &&
      other.query == query &&
      other.sort == sort &&
      _sameSet(other.folders, folders) &&
      _sameSet(other.match, match);

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  int get hashCode => Object.hash(
    query,
    sort,
    Object.hashAllUnordered(folders),
    Object.hashAllUnordered(match),
  );

  @override
  String toString() =>
      'BackupFilter(query: $query, folders: $folders, match: $match, '
      'sort: $sort)';
}

/// Owns the [BackupFilter] of the Backups tab.
final class BackupFilterController extends Notifier<BackupFilter> {
  @override
  BackupFilter build() => BackupFilter.empty;

  /// Sets the search text.
  void setQuery(String query) => state = state.copyWith(query: query);

  /// Adds [folder] to the folder filter, or removes it when present.
  void toggleFolder(String folder) {
    final folders = Set<String>.of(state.folders);
    if (!folders.remove(folder)) folders.add(folder);
    state = state.copyWith(folders: Set.unmodifiable(folders));
  }

  /// Adds [filter] to the match filter, or removes it when present.
  void toggleMatch(BackupMatchFilter filter) {
    final match = Set<BackupMatchFilter>.of(state.match);
    if (!match.remove(filter)) match.add(filter);
    state = state.copyWith(match: Set.unmodifiable(match));
  }

  /// Changes the sort order.
  void setSort(BackupSortOption sort) => state = state.copyWith(sort: sort);

  /// Clears every filter but keeps the search text and the sort order
  /// ("Clear all filters" in the toolbar).
  void clearFilters() =>
      state = BackupFilter(query: state.query, sort: state.sort);

  /// Clears the search text and every filter; the sort order is kept.
  void clear() => state = BackupFilter(sort: state.sort);
}

/// The current [BackupFilter].
final backupFilterProvider =
    NotifierProvider<BackupFilterController, BackupFilter>(
      BackupFilterController.new,
    );

/// Parent folder names of every backup (the choices of the folder filter),
/// in alphabetical order.
final availableBackupFoldersProvider = Provider<Set<String>>((ref) {
  final backups = ref.watch(
    libraryControllerProvider.select((s) => s.value?.backups),
  );
  if (backups == null) return const {};
  final folders = {for (final backup in backups) backup.folder}.toList()
    ..sort();
  return Set.unmodifiable(folders);
});

/// The backups after search, filters and sort (port of 2.x
/// `filteredBackupsProvider`).
///
/// - search: `fileName` contains the query, case-insensitive;
/// - folders: the backup's folder must be in the set;
/// - match: `hasMatchingMod` must agree with at least one chosen value;
/// - sort: name, size or modification date, each both ways. Size and date
///   sorts break ties by name so the order is stable.
///
/// While a refresh runs the previous state is used, so the list never
/// flickers empty.
final filteredBackupsProvider = Provider<List<Backup>>((ref) {
  final filter = ref.watch(backupFilterProvider);
  final backups = ref.watch(
    libraryControllerProvider.select((s) => s.value?.backups),
  );
  if (backups == null) return const [];

  final query = filter.query.trim().toLowerCase();
  final filtered = [
    for (final backup in backups)
      if (_matches(backup, filter, query)) backup,
  ];
  filtered.sort(_comparatorFor(filter.sort));
  return filtered;
});

bool _matches(Backup backup, BackupFilter filter, String query) {
  if (query.isNotEmpty && !backup.fileName.toLowerCase().contains(query)) {
    return false;
  }
  if (filter.folders.isNotEmpty && !filter.folders.contains(backup.folder)) {
    return false;
  }
  if (filter.match.isNotEmpty) {
    final wanted = backup.hasMatchingMod
        ? BackupMatchFilter.hasMatchingMod
        : BackupMatchFilter.noMatchingMod;
    if (!filter.match.contains(wanted)) return false;
  }
  return true;
}

int _byName(Backup a, Backup b) =>
    a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());

Comparator<Backup> _comparatorFor(BackupSortOption sort) => switch (sort) {
  BackupSortOption.nameAsc => _byName,
  BackupSortOption.nameDesc => (a, b) => _byName(b, a),
  BackupSortOption.sizeDesc => (a, b) {
    final bySize = b.sizeBytes.compareTo(a.sizeBytes);
    return bySize != 0 ? bySize : _byName(a, b);
  },
  BackupSortOption.sizeAsc => (a, b) {
    final bySize = a.sizeBytes.compareTo(b.sizeBytes);
    return bySize != 0 ? bySize : _byName(a, b);
  },
  BackupSortOption.dateDesc => (a, b) {
    final byDate = b.modified.compareTo(a.modified);
    return byDate != 0 ? byDate : _byName(a, b);
  },
  BackupSortOption.dateAsc => (a, b) {
    final byDate = a.modified.compareTo(b.modified);
    return byDate != 0 ? byDate : _byName(a, b);
  },
};

/// The selected backups as a set of archive paths. One path means a single
/// selection (the detail panel), several mean a bulk selection.
final class BackupSelectionController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Selects exactly [path].
  void select(String path) => state = {path};

  /// Adds [path] to the selection, or removes it when selected (Ctrl-click).
  void toggle(String path) {
    final paths = Set<String>.of(state);
    if (!paths.remove(path)) paths.add(path);
    state = Set.unmodifiable(paths);
  }

  /// Deselects everything.
  void clear() => state = const {};
}

/// The selected backup paths.
final backupSelectionProvider =
    NotifierProvider<BackupSelectionController, Set<String>>(
      BackupSelectionController.new,
    );

/// The single selected backup, or null when none or several are selected or
/// the selected path is no longer in the library.
final selectedBackupProvider = Provider<Backup?>((ref) {
  final selection = ref.watch(backupSelectionProvider);
  if (selection.length != 1) return null;
  final path = selection.single;
  return ref.watch(
    libraryControllerProvider.select(
      (s) => s.value?.backups.where((b) => b.path == path).firstOrNull,
    ),
  );
});

/// Every selected backup that is in the library, in selection order.
final selectedBackupsProvider = Provider<List<Backup>>((ref) {
  final selection = ref.watch(backupSelectionProvider);
  if (selection.isEmpty) return const [];
  final backups = ref.watch(
    libraryControllerProvider.select((s) => s.value?.backups),
  );
  if (backups == null) return const [];
  final byPath = {for (final backup in backups) backup.path: backup};
  return [for (final path in selection) ?byPath[path]];
});
