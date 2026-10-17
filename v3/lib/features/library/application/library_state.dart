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
  /// mod with the same `jsonPath`; mods without a stored counterpart are
  /// ignored. Only the lists that actually change get a new instance.
  LibraryState withMods(Iterable<Mod> replacements) {
    final byPath = {for (final mod in replacements) mod.jsonPath: mod};
    if (byPath.isEmpty) return this;

    List<Mod> patch(List<Mod> list) {
      var changed = false;
      final out = <Mod>[];
      for (final mod in list) {
        final replacement = byPath[mod.jsonPath];
        if (replacement != null && replacement.ref.type == mod.ref.type) {
          changed = true;
          out.add(replacement);
        } else {
          out.add(mod);
        }
      }
      return changed ? out : list;
    }

    return copyWith(
      mods: patch(mods),
      saves: patch(saves),
      savedObjects: patch(savedObjects),
    );
  }

  @override
  String toString() =>
      'LibraryState(${mods.length} mods, ${saves.length} saves, '
      '${savedObjects.length} saved objects, ${backups.length} backups, '
      'lastRefresh: $lastRefresh, ${warnings.length} warnings)';
}
