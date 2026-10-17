import 'package:tts_mod_vault/domain/models/models.dart';

/// The indexed library as shown by the Mods and Backups pages.
///
/// [mods], [saves] and [savedObjects] are the per-type lists in the order the
/// summary query returns them (save name, case-insensitive); [backups] every
/// `.ttsmod` found, with `matchingModPath` filled in where a mod produces its
/// file name. [warnings] are the non-fatal problems of the refresh that
/// produced this state (missing folders, unreadable files).
final class LibraryState {
  /// Creates a state. Lists are taken as given; callers pass fresh ones.
  LibraryState({
    this.mods = const [],
    this.saves = const [],
    this.savedObjects = const [],
    this.backups = const [],
    this.lastRefresh,
    this.warnings = const [],
  });

  /// Nothing indexed yet (before the first refresh).
  static final LibraryState empty = LibraryState();

  /// Workshop mods.
  final List<Mod> mods;

  /// Save games.
  final List<Mod> saves;

  /// Saved objects (empty unless the option is enabled).
  final List<Mod> savedObjects;

  /// Every backup archive found in the backups folder.
  final List<Backup> backups;

  /// When the refresh that produced this state finished; null for [empty].
  final DateTime? lastRefresh;

  /// Non-fatal problems reported by the last refresh.
  final List<String> warnings;

  late final Map<String, Mod> _byPath = {
    for (final mod in all) mod.jsonPath: mod,
  };

  /// Every mod of every type.
  List<Mod> get all => [...mods, ...saves, ...savedObjects];

  /// Total number of indexed mods, saves and saved objects.
  int get count => mods.length + saves.length + savedObjects.length;

  /// Whether nothing has been indexed.
  bool get isEmpty => count == 0 && backups.isEmpty;

  /// The list for [type]; the stored list instance, so `select` on it is
  /// cheap.
  List<Mod> byType(ModType type) => switch (type) {
    ModType.mod => mods,
    ModType.save => saves,
    ModType.savedObject => savedObjects,
  };

  /// The mod with the normalised [jsonPath], or null.
  Mod? modByPath(String jsonPath) => _byPath[jsonPath];

  /// Copy with some fields replaced. `lastRefresh` cannot be reset to null.
  LibraryState copyWith({
    List<Mod>? mods,
    List<Mod>? saves,
    List<Mod>? savedObjects,
    List<Backup>? backups,
    DateTime? lastRefresh,
    List<String>? warnings,
  }) => LibraryState(
    mods: mods ?? this.mods,
    saves: saves ?? this.saves,
    savedObjects: savedObjects ?? this.savedObjects,
    backups: backups ?? this.backups,
    lastRefresh: lastRefresh ?? this.lastRefresh,
    warnings: warnings ?? this.warnings,
  );

  /// Copy in which each mod of [replacements] takes the place of the stored
  /// mod with the same `jsonPath`. Mods without a stored counterpart are
  /// ignored unless [addMissing] is set, in which case they are inserted
  /// into the list of their type at the position the summary query's order
  /// (save name, case-insensitive, then path) gives them. Only the lists
  /// that actually change get a new instance.
  LibraryState withMods(Iterable<Mod> replacements, {bool addMissing = false}) {
    final byPath = {for (final mod in replacements) mod.jsonPath: mod};
    if (byPath.isEmpty) return this;

    List<Mod> patch(List<Mod> list, ModType type) {
      var changed = false;
      final out = <Mod>[];
      final seen = <String>{};
      for (final mod in list) {
        final replacement = byPath[mod.jsonPath];
        if (replacement != null && replacement.ref.type == mod.ref.type) {
          changed = true;
          seen.add(mod.jsonPath);
          out.add(replacement);
        } else {
          out.add(mod);
        }
      }
      if (addMissing) {
        for (final mod in byPath.values) {
          if (mod.ref.type != type || seen.contains(mod.jsonPath)) continue;
          if (_byPath.containsKey(mod.jsonPath)) continue;
          changed = true;
          out.insert(_insertionIndex(out, mod), mod);
        }
      }
      return changed ? out : list;
    }

    return copyWith(
      mods: patch(mods, ModType.mod),
      saves: patch(saves, ModType.save),
      savedObjects: patch(savedObjects, ModType.savedObject),
    );
  }

  /// Copy without the mod at [jsonPath]; a backup that pointed at it loses
  /// its `matchingModPath`. Returns `this` when the path is unknown.
  LibraryState withoutMod(String jsonPath) {
    final removed = modByPath(jsonPath);
    if (removed == null) return this;
    List<Mod> drop(List<Mod> list, ModType type) => removed.ref.type == type
        ? [
            for (final mod in list)
              if (mod.jsonPath != jsonPath) mod,
          ]
        : list;
    final detached = backups.any((b) => b.matchingModPath == jsonPath)
        ? [
            for (final backup in backups)
              backup.matchingModPath == jsonPath
                  ? backup.copyWith(matchingModPath: null)
                  : backup,
          ]
        : backups;
    return copyWith(
      mods: drop(mods, ModType.mod),
      saves: drop(saves, ModType.save),
      savedObjects: drop(savedObjects, ModType.savedObject),
      backups: detached,
    );
  }

  /// Copy in which the backup at [oldPath] is replaced by [replacement]
  /// (which may live at another path, after a rename). Returns `this` when
  /// [oldPath] is unknown.
  LibraryState withBackupReplaced(String oldPath, Backup replacement) {
    final index = backups.indexWhere((b) => b.path == oldPath);
    if (index < 0) return this;
    final patched = List<Backup>.of(backups);
    patched[index] = replacement;
    return copyWith(backups: patched);
  }

  /// Copy in which [backup] replaces the stored backup with the same path
  /// or, when none has that path, is appended. Returns `this` when the
  /// stored backup is equal to [backup].
  LibraryState withBackupUpserted(Backup backup) {
    final index = backups.indexWhere((b) => b.path == backup.path);
    if (index >= 0 && backups[index] == backup) return this;
    final patched = List<Backup>.of(backups);
    if (index >= 0) {
      patched[index] = backup;
    } else {
      patched.add(backup);
    }
    return copyWith(backups: patched);
  }

  /// Copy without the backup at [path]. Mods that pointed at it keep their
  /// stale `backup` until they are re-summarised. Returns `this` when the
  /// path is unknown.
  LibraryState withoutBackup(String path) {
    if (!backups.any((b) => b.path == path)) return this;
    return copyWith(
      backups: [
        for (final backup in backups)
          if (backup.path != path) backup,
      ],
    );
  }

  /// Index at which [mod] keeps [list] in the summary query's order.
  static int _insertionIndex(List<Mod> list, Mod mod) {
    final key = _orderKey(mod);
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_compareKeys(_orderKey(list[mid]), key) <= 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  static (String, String) _orderKey(Mod mod) =>
      (mod.saveName.toLowerCase(), mod.jsonPath);

  static int _compareKeys((String, String) a, (String, String) b) {
    final byName = a.$1.compareTo(b.$1);
    return byName != 0 ? byName : a.$2.compareTo(b.$2);
  }

  @override
  String toString() =>
      'LibraryState(${mods.length} mods, ${saves.length} saves, '
      '${savedObjects.length} saved objects, ${backups.length} backups, '
      'lastRefresh: $lastRefresh, ${warnings.length} warnings)';
}
