import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/error_message.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/app/widgets/progress_message.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/images_viewer/presentation/images_viewer_grid_card.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Widest a grid tile gets; the grid fits as many columns as that allows.
const double _maxTileExtent = 256;

/// Pushes the full-screen images viewer for [mod]; completes when it is
/// closed.
Future<void> openImagesViewer(BuildContext context, Mod mod) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ImagesViewerPage(mod: mod),
      ),
    );

/// Full-screen grid of a mod's downloaded images.
///
/// Reads the mod's assets through [modAssetsProvider] and keeps the image
/// assets that are on disk. The app bar has a Back button, the title
/// `<name> – N images` and a help icon; Esc pops the page. Loose port of 2.x
/// `ImagesViewerPage`.
class ImagesViewerPage extends ConsumerWidget {
  /// Creates the page for [mod].
  const ImagesViewerPage({super.key, required this.mod});

  /// The mod whose images are shown.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final images = ref
        .watch(modAssetsProvider(mod.jsonPath))
        .whenData(downloadedImages);

    final title = switch (images) {
      AsyncData(:final value) => l10n.imagesViewerTitle(
        mod.displayName,
        value.length,
      ),
      _ => mod.displayName,
    };

    void pop() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): pop},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: pop),
            title: Text(title, overflow: TextOverflow.ellipsis),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: Insets.lg),
                child: Tooltip(
                  message: l10n.imagesViewerHelp,
                  child: Icon(
                    Icons.info_outline,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          body: switch (images) {
            AsyncData(:final value) => _ImagesGrid(mod: mod, images: value),
            AsyncError(:final error) => Center(
              child: ErrorMessage(
                error: error,
                onRetry: () => ref.invalidate(modAssetsProvider(mod.jsonPath)),
              ),
            ),
            _ => Center(
              child: ProgressMessage(message: l10n.imagesViewerLoading),
            ),
          },
        ),
      ),
    );
  }
}

/// The image assets of [assets] whose file is on disk, in the given order.
List<Asset> downloadedImages(List<Asset> assets) => [
  for (final asset in assets)
    if (asset.type == AssetType.image && asset.exists) asset,
];

class _ImagesGrid extends StatelessWidget {
  const _ImagesGrid({required this.mod, required this.images});

  final Mod mod;
  final List<Asset> images;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Text(
          AppLocalizations.of(context).imagesViewerEmpty,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(Insets.lg),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _maxTileExtent,
        mainAxisSpacing: Insets.lg,
        crossAxisSpacing: Insets.lg,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) =>
          ImagesViewerGridCard(mod: mod, asset: images[index]),
    );
  }
}
