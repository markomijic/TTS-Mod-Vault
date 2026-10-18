import 'package:hooks_riverpod/hooks_riverpod.dart';

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
