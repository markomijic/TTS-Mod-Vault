import 'dart:async' show Timer, unawaited;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useFuture, useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/data/pdf/pdf_thumbnail_renderer.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_context_menu.dart';
import 'package:tts_mod_vault/features/images_viewer/presentation/asset_file_actions.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// How long a tile must stay in the tree before its render starts, so
/// scrolling quickly past the PDF section does not queue work (or allocate
/// pixel buffers) for tiles the user never lingers on.
const Duration pdfThumbnailRenderDelay = Duration(milliseconds: 300);

/// Width of the hover border.
const double _borderWidth = 3;

/// Duration of the hover border animation.
const Duration _borderDuration = Duration(milliseconds: 150);

/// Size of the placeholder icon relative to the tile.
const double _iconFraction = 0.3;

/// The first page of a downloaded PDF as a fixed [size] x [size] tile with
/// the URL's tail as caption.
///
/// Render lifecycle: the tile owns its render. When it is mounted with a
/// file on disk it waits [pdfThumbnailRenderDelay], then asks the
/// [pdfThumbnailRendererProvider] for PNG bytes and keeps them only in its
/// own hook state; the decoded bitmap is a tile-sized [ResizeImage] that is
/// evicted from Flutter's image cache when the tile is disposed. Because
/// list and grid builders dispose off-screen children, scrolling a PDF out
/// of view frees everything and scrolling it back in renders it again:
/// there is no cache beyond the widget's state, on purpose (RAM).
///
/// A placeholder with a PDF icon is shown while loading, when the file is
/// not downloaded ([Asset.path] is null) and when rendering failed. Left
/// click opens the file, right click shows the full asset context menu
/// (the same one the URL rows offer).
class PdfThumbnail extends HookConsumerWidget {
  /// Creates the tile for [asset] of [mod].
  const PdfThumbnail({
    super.key,
    required this.mod,
    required this.asset,
    this.size = 192,
  });

  /// The mod the asset belongs to (for the context menu actions).
  final Mod mod;

  /// The PDF asset.
  final Asset asset;

  /// Edge length of the square tile in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = VaultColors.of(context);
    final renderer = ref.watch(pdfThumbnailRendererProvider);
    final path = asset.path;
    final hovered = useState(false);

    // Arm the render after the delay; a new path re-arms from scratch.
    final armed = useState(false);
    useEffect(() {
      armed.value = false;
      if (path == null) return null;
      final timer = Timer(pdfThumbnailRenderDelay, () => armed.value = true);
      return timer.cancel;
    }, [path]);

    final future = useMemoized(
      () => path != null && armed.value ? renderer.renderFirstPage(path) : null,
      [path, armed.value, renderer],
    );
    final snapshot = useFuture(future);
    final Uint8List? bytes = snapshot.data;

    // Decode at tile size so the retained bitmap is tile-sized, not
    // render-sized, and drop it from the image cache with the tile.
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final imageProvider = useMemoized(
      () => bytes == null
          ? null
          : ResizeImage(MemoryImage(bytes), height: cacheSize),
      [bytes, cacheSize],
    );
    useEffect(
      () =>
          () => unawaited(imageProvider?.evict()),
      [imageProvider],
    );

    final failed =
        path != null &&
        future != null &&
        (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                bytes == null));

    final Widget content;
    if (path == null) {
      content = _Placeholder(
        size: size,
        icon: Icons.picture_as_pdf_outlined,
        iconColor: colors.assetMissing,
        label: l10n.pdfNotDownloaded,
      );
    } else if (imageProvider != null) {
      content = Image(
        image: imageProvider,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _Placeholder(
          size: size,
          icon: Icons.picture_as_pdf_outlined,
          iconColor: colors.assetInvalid,
          label: l10n.pdfRenderFailed,
        ),
      );
    } else if (failed) {
      content = _Placeholder(
        size: size,
        icon: Icons.picture_as_pdf_outlined,
        iconColor: colors.assetInvalid,
        label: l10n.pdfRenderFailed,
      );
    } else {
      content = _Placeholder(
        size: size,
        icon: Icons.picture_as_pdf_outlined,
        iconColor: scheme.onSurfaceVariant,
      );
    }

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
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border.all(
                width: _borderWidth,
                color: hovered.value ? scheme.outline : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(Insets.sm),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Insets.sm - _borderWidth),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  content,
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

/// Icon (and optional label) centred on a surface tile.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.size,
    required this.icon,
    required this.iconColor,
    this.label,
  });

  final double size;
  final IconData icon;
  final Color iconColor;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = this.label;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: size * _iconFraction, color: iconColor),
            if (label != null) ...[
              Gaps.h8,
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: iconColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One-line caption band at the bottom of an asset tile.
class AssetCaption extends StatelessWidget {
  /// Creates the caption.
  const AssetCaption({super.key, required this.text});

  /// Text shown on one line, ellipsised.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ColoredBox(
      color: scheme.surface.withValues(alpha: 0.8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.sm,
          vertical: Insets.xs,
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurface),
        ),
      ),
    );
  }
}
