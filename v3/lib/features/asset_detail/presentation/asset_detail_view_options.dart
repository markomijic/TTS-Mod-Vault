import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart'
    show keyValueStoreProvider;
import 'package:tts_mod_vault/core/storage/key_value_store.dart';

/// Font size of the URLs in the asset list, persisted on its own under
/// [AssetUrlFontSizeController.storageKey].
///
/// This is the one user-configurable font size in the app (2.x
/// `assetUrlFontSize`). Phase 5 moves it into the Settings dialog; the
/// provider stays.
final class AssetUrlFontSizeController extends Notifier<double> {
  /// Store key under which the size lives.
  static const String storageKey = 'assetDetail.urlFontSize';

  /// The 2.x default.
  static const double defaultSize = 12;

  /// Smallest accepted size.
  static const double minSize = 8;

  /// Largest accepted size.
  static const double maxSize = 24;

  bool _touched = false;

  @override
  double build() {
    final store = ref.watch(keyValueStoreProvider);
    _touched = false;
    _restore(store);
    return defaultSize;
  }

  Future<void> _restore(KeyValueStore store) async {
    final raw = await store.read(storageKey);
    if (!ref.mounted || _touched || raw == null) return;
    final parsed = double.tryParse(raw);
    if (parsed != null) state = clamp(parsed);
  }

  /// Clamps [size] to [minSize]..[maxSize].
  static double clamp(double size) => size.clamp(minSize, maxSize).toDouble();

  /// Sets and persists the size, clamped to the accepted range.
  Future<void> set(double size) async {
    _touched = true;
    state = clamp(size);
    await ref.read(keyValueStoreProvider).write(storageKey, state.toString());
  }
}

/// The current URL font size.
final assetUrlFontSizeProvider =
    NotifierProvider<AssetUrlFontSizeController, double>(
      AssetUrlFontSizeController.new,
    );

/// The URL the user clicked last in the asset list (highlighted in the
/// primary colour), or null.
final class SelectedAssetUrlController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Highlights [url].
  void select(String url) => state = url;

  /// Highlights [url], or clears the highlight when it is already selected.
  void toggle(String url) => state = state == url ? null : url;

  /// Clears the highlight.
  void clear() => state = null;
}

/// The selected asset URL.
final selectedAssetUrlProvider =
    NotifierProvider<SelectedAssetUrlController, String?>(
      SelectedAssetUrlController.new,
    );
