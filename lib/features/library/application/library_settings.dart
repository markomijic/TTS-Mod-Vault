import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';

/// The settings the library refresh depends on.
///
/// Defaults match 2.x (`ignoreAudioAssets: true`, `showSavedObjects: false`,
/// `forceBackupJsonFilename: false`, no ignored subfolders). Phase 5 moves
/// these into the full `Settings` model; until then they are persisted on
/// their own under [LibraryOptionsController.storageKey].
final class LibraryOptions {
  /// Creates the options.
  const LibraryOptions({
    this.ignoredSubfolders = const [],
    this.includeSavedObjects = false,
    this.ignoreAudioGlobally = true,
    this.forceBackupIdInName = false,
  });

  /// Reads options from their JSON form; malformed fields fall back to the
  /// defaults.
  factory LibraryOptions.fromJson(Map<String, Object?> json) {
    const defaults = LibraryOptions();
    final folders = json['ignoredSubfolders'];
    return LibraryOptions(
      ignoredSubfolders: folders is List
          ? [
              for (final folder in folders)
                if (folder is String && folder.isNotEmpty) folder,
            ]
          : defaults.ignoredSubfolders,
      includeSavedObjects: switch (json['includeSavedObjects']) {
        final bool value => value,
        _ => defaults.includeSavedObjects,
      },
      ignoreAudioGlobally: switch (json['ignoreAudioGlobally']) {
        final bool value => value,
        _ => defaults.ignoreAudioGlobally,
      },
      forceBackupIdInName: switch (json['forceBackupIdInName']) {
        final bool value => value,
        _ => defaults.forceBackupIdInName,
      },
    );
  }

  /// The 2.x defaults.
  static const LibraryOptions defaults = LibraryOptions();

  /// Folder names skipped when scanning for mods and saves (whole path
  /// segment, case-sensitive).
  final List<String> ignoredSubfolders;

  /// Whether `Saves/Saved Objects` is scanned and shown.
  final bool includeSavedObjects;

  /// Whether audio assets are hidden from counts unless a mod overrides it.
  final bool ignoreAudioGlobally;

  /// Whether Workshop mods with a non-numeric id get the id in their backup
  /// file name (`<name> (<id>).ttsmod`).
  final bool forceBackupIdInName;

  /// JSON form for the key-value store.
  Map<String, Object?> toJson() => {
    'ignoredSubfolders': ignoredSubfolders,
    'includeSavedObjects': includeSavedObjects,
    'ignoreAudioGlobally': ignoreAudioGlobally,
    'forceBackupIdInName': forceBackupIdInName,
  };

  /// Copy with some fields replaced.
  LibraryOptions copyWith({
    List<String>? ignoredSubfolders,
    bool? includeSavedObjects,
    bool? ignoreAudioGlobally,
    bool? forceBackupIdInName,
  }) => LibraryOptions(
    ignoredSubfolders: ignoredSubfolders ?? this.ignoredSubfolders,
    includeSavedObjects: includeSavedObjects ?? this.includeSavedObjects,
    ignoreAudioGlobally: ignoreAudioGlobally ?? this.ignoreAudioGlobally,
    forceBackupIdInName: forceBackupIdInName ?? this.forceBackupIdInName,
  );

  @override
  bool operator ==(Object other) =>
      other is LibraryOptions &&
      other.includeSavedObjects == includeSavedObjects &&
      other.ignoreAudioGlobally == ignoreAudioGlobally &&
      other.forceBackupIdInName == forceBackupIdInName &&
      other.ignoredSubfolders.length == ignoredSubfolders.length &&
      _sameFolders(other.ignoredSubfolders);

  bool _sameFolders(List<String> other) {
    for (var i = 0; i < other.length; i++) {
      if (other[i] != ignoredSubfolders[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ignoredSubfolders),
    includeSavedObjects,
    ignoreAudioGlobally,
    forceBackupIdInName,
  );

  @override
  String toString() =>
      'LibraryOptions(ignoredSubfolders: $ignoredSubfolders, '
      'includeSavedObjects: $includeSavedObjects, '
      'ignoreAudioGlobally: $ignoreAudioGlobally, '
      'forceBackupIdInName: $forceBackupIdInName)';
}

/// Holds the current [LibraryOptions] and persists changes as JSON in the
/// key-value store.
///
/// Starts with [LibraryOptions.defaults] and swaps in the stored value when
/// the store answers, unless something was changed in the meantime. Code
/// that must not run with provisional defaults (the library refresh) awaits
/// [loaded] first.
final class LibraryOptionsController extends Notifier<LibraryOptions> {
  /// Store key under which the options JSON lives.
  static const String storageKey = 'library.options';

  bool _touched = false;
  late Future<void> _loaded;

  /// Waits until the stored options have been read (or found absent) and
  /// returns the current options.
  Future<LibraryOptions> ensureLoaded() async {
    await _loaded;
    return state;
  }

  @override
  LibraryOptions build() {
    final store = ref.watch(keyValueStoreProvider);
    _touched = false;
    _loaded = _restore(store);
    return LibraryOptions.defaults;
  }

  Future<void> _restore(KeyValueStore store) async {
    final raw = await store.read(storageKey);
    if (!ref.mounted || _touched || raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        state = LibraryOptions.fromJson(json);
      }
    } on FormatException {
      // Corrupt record: keep defaults; the next write replaces it.
    }
  }

  /// Replaces the options and persists them.
  Future<void> set(LibraryOptions options) async {
    _touched = true;
    state = options;
    await ref
        .read(keyValueStoreProvider)
        .write(storageKey, jsonEncode(options.toJson()));
  }

  /// Sets the folders skipped while scanning.
  Future<void> setIgnoredSubfolders(List<String> folders) =>
      set(state.copyWith(ignoredSubfolders: List.unmodifiable(folders)));

  /// Shows or hides saved objects.
  Future<void> setIncludeSavedObjects(bool value) =>
      set(state.copyWith(includeSavedObjects: value));

  /// Hides or shows audio assets globally.
  Future<void> setIgnoreAudioGlobally(bool value) =>
      set(state.copyWith(ignoreAudioGlobally: value));

  /// Toggles the "force id in backup name" rule.
  Future<void> setForceBackupIdInName(bool value) =>
      set(state.copyWith(forceBackupIdInName: value));
}

/// Provides the current [LibraryOptions].
final libraryOptionsProvider =
    NotifierProvider<LibraryOptionsController, LibraryOptions>(
      LibraryOptionsController.new,
    );
