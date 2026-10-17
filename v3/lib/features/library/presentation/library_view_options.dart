import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart'
    show keyValueStoreProvider;
import 'package:tts_mod_vault/core/storage/key_value_store.dart';

/// How the Mods page shows its items.
///
/// Defaults match 2.x: grid, no titles on cards, backup state shown. Phase 5
/// folds these into the Settings dialog; until then they are persisted on
/// their own under [LibraryViewOptionsController.storageKey].
@immutable
final class LibraryViewOptions {
  /// Creates the options.
  const LibraryViewOptions({
    this.useListView = false,
    this.showTitleOnCards = false,
    this.showBackupState = true,
  });

  /// Reads options from their JSON form; malformed fields keep the default.
  factory LibraryViewOptions.fromJson(Map<String, Object?> json) {
    const d = LibraryViewOptions();
    return LibraryViewOptions(
      useListView: switch (json['useListView']) {
        final bool v => v,
        _ => d.useListView,
      },
      showTitleOnCards: switch (json['showTitleOnCards']) {
        final bool v => v,
        _ => d.showTitleOnCards,
      },
      showBackupState: switch (json['showBackupState']) {
        final bool v => v,
        _ => d.showBackupState,
      },
    );
  }

  /// The 2.x defaults.
  static const LibraryViewOptions defaults = LibraryViewOptions();

  /// Rows instead of cards.
  final bool useListView;

  /// Show the name band at the bottom of every grid card.
  final bool showTitleOnCards;

  /// Show the backup status badge on cards and rows.
  final bool showBackupState;

  /// JSON form for the key-value store.
  Map<String, Object?> toJson() => {
    'useListView': useListView,
    'showTitleOnCards': showTitleOnCards,
    'showBackupState': showBackupState,
  };

  /// Copy with some fields replaced.
  LibraryViewOptions copyWith({
    bool? useListView,
    bool? showTitleOnCards,
    bool? showBackupState,
  }) => LibraryViewOptions(
    useListView: useListView ?? this.useListView,
    showTitleOnCards: showTitleOnCards ?? this.showTitleOnCards,
    showBackupState: showBackupState ?? this.showBackupState,
  );

  @override
  bool operator ==(Object other) =>
      other is LibraryViewOptions &&
      other.useListView == useListView &&
      other.showTitleOnCards == showTitleOnCards &&
      other.showBackupState == showBackupState;

  @override
  int get hashCode =>
      Object.hash(useListView, showTitleOnCards, showBackupState);

  @override
  String toString() =>
      'LibraryViewOptions(useListView: $useListView, '
      'showTitleOnCards: $showTitleOnCards, showBackupState: $showBackupState)';
}

/// Holds the current [LibraryViewOptions] and persists changes as JSON.
///
/// Starts with [LibraryViewOptions.defaults] and swaps in the stored value
/// when the store answers, unless something was changed in the meantime.
final class LibraryViewOptionsController extends Notifier<LibraryViewOptions> {
  /// Store key under which the options JSON lives.
  static const String storageKey = 'library.view';

  bool _touched = false;

  @override
  LibraryViewOptions build() {
    final store = ref.watch(keyValueStoreProvider);
    _touched = false;
    _restore(store);
    return LibraryViewOptions.defaults;
  }

  Future<void> _restore(KeyValueStore store) async {
    final raw = await store.read(storageKey);
    if (!ref.mounted || _touched || raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        state = LibraryViewOptions.fromJson(json);
      }
    } on FormatException {
      // Corrupt record: keep defaults; the next write replaces it.
    }
  }

  /// Replaces the options and persists them.
  Future<void> set(LibraryViewOptions options) async {
    _touched = true;
    state = options;
    await ref
        .read(keyValueStoreProvider)
        .write(storageKey, jsonEncode(options.toJson()));
  }

  /// Switches between grid and list.
  Future<void> setUseListView(bool value) =>
      set(state.copyWith(useListView: value));

  /// Flips between grid and list.
  Future<void> toggleListView() => setUseListView(!state.useListView);

  /// Shows or hides the title band on grid cards.
  Future<void> setShowTitleOnCards(bool value) =>
      set(state.copyWith(showTitleOnCards: value));

  /// Shows or hides the backup status badge.
  Future<void> setShowBackupState(bool value) =>
      set(state.copyWith(showBackupState: value));
}

/// Provides the current [LibraryViewOptions].
final libraryViewOptionsProvider =
    NotifierProvider<LibraryViewOptionsController, LibraryViewOptions>(
      LibraryViewOptionsController.new,
    );
