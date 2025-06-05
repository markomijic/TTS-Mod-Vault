import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart' show HookConsumer;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/utils.dart'
    show
        copyToClipboard,
        getFileNameFromPath,
        openImageFile,
        openInFileExplorer,
        openUrl,
        showSnackBar;

void showImagesViewer(
  BuildContext context,
  List<Asset> existingImages,
  int totalImagesCount,
  String modSaveName,
) {
  if (context.mounted) {
    if (existingImages.isEmpty) {
      showSnackBar(context, "$modSaveName doesn't have any downloaded images");
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return ImagesViewer(
          existingImages: existingImages,
          totalImagesCount: totalImagesCount,
          modSaveName: modSaveName,
        );
      },
    );
  }
}

class ImagesViewer extends StatelessWidget {
  final List<Asset> existingImages;
  final int totalImagesCount;
  final String modSaveName;

  const ImagesViewer({
    super.key,
    required this.existingImages,
    required this.totalImagesCount,
    required this.modSaveName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "(${existingImages.length}/$totalImagesCount) ",
              style: TextStyle(
                overflow: TextOverflow.ellipsis,
                fontSize: 30,
              ),
            ),
            Expanded(
              child: Text(
                modSaveName,
                style: TextStyle(
                  overflow: TextOverflow.ellipsis,
                  fontSize: 30,
                ),
              ),
            ),
          ],
        ),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount =
              constraints.maxWidth > 500 ? constraints.maxWidth ~/ 220 : 1;

          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              crossAxisCount: crossAxisCount,
            ),
            itemCount: existingImages.length,
            itemBuilder: (context, index) {
              final asset = existingImages[index];

              return ImagesViewerGridCard(asset: asset);
            },
          );
        },
      ),
    );
  }
}

class ImagesViewerGridCard extends StatelessWidget {
  final Asset asset;

  const ImagesViewerGridCard({
    super.key,
    required this.asset,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Image.file(
          File(asset.filePath!),
          height: 256,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.black,
              child: Center(
                  child: Text(
                'Failed to load image',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              )),
            );
          },
        ),
        HookConsumer(
          builder: (context, ref, child) {
            final isHovered = useState(false);

            return MouseRegion(
              onEnter: (event) => isHovered.value = true,
              onExit: (event) => isHovered.value = false,
              child: Visibility(
                visible: isHovered.value,
                replacement: Container(),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white,
                            width: 4,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: "Open URL in Browser",
                                onPressed: () => openUrl(asset.url),
                                icon: const Icon(Icons.open_in_browser),
                                style: IconButton.styleFrom(
                                    backgroundColor: Colors.black),
                              ),
                              IconButton(
                                tooltip: "Open in File Explorer",
                                onPressed: () =>
                                    openInFileExplorer(asset.filePath!),
                                icon: const Icon(Icons.folder_open),
                                style: IconButton.styleFrom(
                                    backgroundColor: Colors.black),
                              ),
                              IconButton(
                                tooltip: "Open File",
                                onPressed: () => openImageFile(asset.filePath!),
                                icon: const Icon(Icons.folder_special),
                                style: IconButton.styleFrom(
                                    backgroundColor: Colors.black),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: "Copy URL",
                                onPressed: () =>
                                    copyToClipboard(context, asset.url),
                                icon: const Icon(Icons.copy),
                                style: IconButton.styleFrom(
                                    backgroundColor: Colors.black),
                              ),
                              IconButton(
                                tooltip: "Copy Filename",
                                onPressed: () => copyToClipboard(
                                  context,
                                  getFileNameFromPath(asset.filePath ?? ''),
                                ),
                                icon: const Icon(Icons.file_copy),
                                style: IconButton.styleFrom(
                                    backgroundColor: Colors.black),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
