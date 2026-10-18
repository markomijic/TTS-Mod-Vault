import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:tts_mod_vault/app/theme/theme_presets.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';

/// The persistent key-value store used by the app shell.
///
/// Must be overridden in `main.dart` (with the SQLite-backed store) and in
/// tests (with [InMemoryKeyValueStore]); reading it without an override
/// throws.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError('override in main'),
);

/// Holds the current [ThemeSettings] and persists changes.
///
/// The notifier starts with [ThemeSettings.defaults] and swaps in the stored
/// value as soon as the store answers, unless the user changed something in
/// the meantime.
final class ThemeController extends Notifier<ThemeSettings> {
  /// Store key under which the settings JSON lives.
  static const String storageKey = 'theme.settings';

  bool _touched = false;

  @override
  ThemeSettings build() {
    final store = ref.watch(keyValueStoreProvider);
    _touched = false;
    _restore(store);
    return ThemeSettings.defaults();
  }

  Future<void> _restore(KeyValueStore store) async {
    final raw = await store.read(storageKey);
    if (!ref.mounted || _touched || raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      state = ThemeSettings.fromJson(json);
    } on FormatException {
      // Corrupt record: keep defaults; the next write replaces it.
    } on TypeError {
      // Not a JSON object: keep defaults; the next write replaces it.
    }
  }

  /// Replaces the settings and persists them.
  Future<void> set(ThemeSettings settings) async {
    _touched = true;
    state = settings;
    await ref
        .read(keyValueStoreProvider)
        .write(storageKey, jsonEncode(settings.toJson()));
  }

  /// Switches between light, dark and system mode.
  Future<void> setMode(ThemeMode mode) => set(state.copyWith(mode: mode));

  /// Uses a custom seed colour (ARGB); clears the preset id.
  Future<void> setSeed(int seedColor) =>
      set(state.copyWith(seedColor: seedColor, clearPresetId: true));

  /// Applies the preset with [id]; unknown ids are ignored.
  Future<void> applyPreset(String id) async {
    final preset = ThemePresets.byId(id);
    if (preset == null) return;
    await set(
      state.copyWith(
        seedColor: preset.seed,
        variant: preset.variant,
        presetId: preset.id,
      ),
    );
  }
}

/// Provides the current [ThemeSettings].
final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);
