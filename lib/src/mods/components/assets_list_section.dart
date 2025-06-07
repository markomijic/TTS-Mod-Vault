import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show AssetsUrl;
import 'package:tts_mod_vault/src/mods/components/images_viewer.dart'
    show showImagesViewer;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        downloadProvider,
        modsProvider,
        selectedModProvider;

class AssetsListSection extends HookConsumerWidget {
  final AssetTypeEnum type;
  final List<Asset> assets;

  const AssetsListSection({
    super.key,
    required this.type,
    required this.assets,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadNotifier = ref.watch(downloadProvider.notifier);
    final actionInProgress = ref.watch(actionInProgressProvider);
    final selectedMod = ref.watch(selectedModProvider);

    final hasMissingFiles = useMemoized(
      () => assets.any((e) => !e.fileExists),
      [assets],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                bottom: BorderSide(
                  color: Colors.white,
                  width: 2.0,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 2,
              children: [
                Text(
                  type.label,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (hasMissingFiles && !actionInProgress)
                  Tooltip(
                    message: "Download all missing ${type.label.toLowerCase()}",
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: TextStyle(color: Colors.white),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          if (selectedMod == null) {
                            return;
                          }

                          final urls = assets
                              .map((e) => e.fileExists ? null : e.url)
                              .nonNulls
                              .toList();

                          await downloadNotifier.downloadFiles(
                            modName: selectedMod.saveName,
                            modAssetListUrls: urls,
                            type: type,
                            downloadingAllFiles: false,
                          );

                          await ref
                              .read(modsProvider.notifier)
                              .updateModBySaveName(selectedMod.saveName);
                        },
                        child: Icon(Icons.download, size: 20),
                      ),
                    ),
                  ),
                if (!actionInProgress && type == AssetTypeEnum.image)
                  Tooltip(
                    message: "Open Images Viewer",
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: TextStyle(color: Colors.white),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          if (selectedMod == null) {
                            return;
                          }

                          if (context.mounted) {
                            final existingImages = selectedMod
                                .getAssetsByType(AssetTypeEnum.image)
                                .where((element) =>
                                    element.fileExists &&
                                    element.filePath != null &&
                                    element.filePath!.isNotEmpty)
                                .toList();
                            showImagesViewer(
                              context,
                              existingImages,
                              selectedMod.assetLists?.images.length ?? 0,
                              selectedMod.saveName,
                            );
                          }
                        },
                        child: Icon(Icons.image, size: 20),
                      ),
                    ),
                  )
              ],
            ),
          ),
          ...assets.map((asset) {
            return AssetsUrl(asset: asset, type: type);
          }),
        ],
      ),
    );
  }
}
