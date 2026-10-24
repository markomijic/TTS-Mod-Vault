import 'dart:io' show File;

import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_context_menu.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/pdf_thumbnail.dart'
    show AssetCaption;
import 'package:tts_mod_vault/features/images_viewer/presentation/asset_file_actions.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Decoded width of a tile; tiles are at most 256 px wide (1.5x for HiDPI).
const int _cacheWidth = 384;

/// Width of the hover border.
const double _borderWidth = 3;

/// Duration of the hover border animation.
const Duration _borderDuration = Duration(milliseconds: 150);

/// Size of the broken-image icon.
const double _errorIconSize = 48;

/// One downloaded image in the images viewer: the file decoded at tile
/// size, the URL's tail as caption and a hover border. Click opens the
/// file, right click shows the full asset context menu (the same one the
/// URL rows offer). Port of 2.x `ImagesViewerGridCard`.
class ImagesViewerGridCard extends HookConsumerWidget {
  /// Creates the card for [asset] of [mod]; [Asset.path] should be
  /// non-null.
  const ImagesViewerGridCard({
    super.key,
    required this.mod,
    required this.asset,
  });

  /// The mod the asset belongs to (for the context menu actions).
  final Mod mod;

  /// The image asset shown.
  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hovered = useState(false);
    final path = asset.path;

    return Tooltip(
      message: asset.url,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => hovered.value = true,
        onExit: (_) => hovered.value = false,
        child: GestureDetector(
          onTap: path == null ? null : () => openAssetFile(context, path),
          onSecondaryTapUp: (details) => showAssetContextMenu(
            context,
            ref,
            details.globalPosition,
            mod,
            asset,
          ),
          child: AnimatedContainer(
            duration: _borderDuration,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border.all(
                width: _borderWidth,
                color: hovered.value ? scheme.outline : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                AppTheme.cardRadius - _borderWidth,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (path == null)
                    const _ImageError()
                  else
                    Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      cacheWidth: _cacheWidth,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const _ImageError(),
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AssetCaption(text: urlTail(asset.url)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: _errorIconSize,
              color: scheme.onSurfaceVariant,
            ),
            Gaps.h8,
            Text(
              AppLocalizations.of(context).imageLoadFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
