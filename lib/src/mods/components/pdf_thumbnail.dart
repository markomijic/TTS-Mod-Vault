import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useFuture, useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/asset_context_menu.dart'
    show showAssetContextMenu;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show pdfThumbnailCacheProvider;
import 'package:tts_mod_vault/src/utils.dart' show getFileNameFromURL, openFile;

/// Renders the first page of a downloaded PDF as a thumbnail.
///
/// For PDFs that are not downloaded (no local [Asset.filePath]) a greyed
/// placeholder tile with the filename is shown instead.
class PdfThumbnail extends HookConsumerWidget {
  final Asset asset;

  const PdfThumbnail({super.key, required this.asset});

  static const double _thumbnailHeight = 192;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHovered = useState(false);
    final fileName = getFileNameFromURL(asset.url);
    final hasFile = asset.fileExists &&
        asset.filePath != null &&
        asset.filePath!.isNotEmpty;

    final cache = ref.read(pdfThumbnailCacheProvider);
    // Synchronous cache hit -> render instantly (no flash on scroll-back).
    final cached = hasFile ? cache.peek(asset.filePath!) : null;

    // Delay kicking off the render so quickly scrolling past the PDF section
    // doesn't start work for tiles the user never lingers on. Cached tiles load
    // immediately.
    final shouldLoad = useState(cached != null);
    useEffect(() {
      if (!hasFile || cached != null) return null;
      final timer = Timer(
        const Duration(milliseconds: 300),
        () => shouldLoad.value = true,
      );
      return timer.cancel;
    }, [asset.filePath, hasFile]);

    final thumbnailFuture = useMemoized(
      () => (hasFile && shouldLoad.value) ? cache.get(asset.filePath!) : null,
      [asset.filePath, hasFile, shouldLoad.value],
    );
    final snapshot = useFuture(thumbnailFuture, initialData: cached);

    Widget content;
    if (!hasFile) {
      content = _PlaceholderTile(
        fileName: fileName,
        icon: Icons.picture_as_pdf,
        label: 'Not downloaded',
        iconColor: Colors.red,
      );
    } else if (snapshot.hasData && snapshot.data != null) {
      content = Image.memory(
        snapshot.data!,
        height: _thumbnailHeight,
        cacheHeight:
            (_thumbnailHeight * MediaQuery.of(context).devicePixelRatio)
                .round(),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _PlaceholderTile(
          fileName: fileName,
          icon: Icons.broken_image,
          label: 'Failed to load PDF',
          iconColor: Colors.orange,
        ),
      );
    } else if (snapshot.hasError ||
        snapshot.connectionState == ConnectionState.done) {
      content = _PlaceholderTile(
        fileName: fileName,
        icon: Icons.broken_image,
        label: 'Failed to load PDF',
        iconColor: Colors.orange,
      );
    } else {
      // Plain fixed-size tile while idle/loading, so the Wrap layout doesn't
      // shift when the thumbnail finishes rendering.
      content = Container(
        height: _thumbnailHeight,
        width: _thumbnailHeight,
        color: Colors.black,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        onTapUp: (details) => showAssetContextMenu(
            context, ref, details.globalPosition, asset, AssetTypeEnum.pdf),
        onSecondaryTapUp: (details) => showAssetContextMenu(
            context, ref, details.globalPosition, asset, AssetTypeEnum.pdf),
        onDoubleTap: () {
          if (hasFile) openFile(asset.filePath!);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            border: Border.all(
              width: 4,
              color: isHovered.value ? Colors.white : Colors.transparent,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  final String fileName;
  final IconData icon;
  final String label;
  final Color iconColor;

  const _PlaceholderTile({
    required this.fileName,
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PdfThumbnail._thumbnailHeight,
      width: PdfThumbnail._thumbnailHeight,
      color: Colors.black,
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      child: Text(
        fileName,
        textAlign: TextAlign.center,
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
    );
  }
}
