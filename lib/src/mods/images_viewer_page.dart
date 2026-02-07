import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show ImagesViewerGridCard, CustomTooltip;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart' show selectedModProvider;

class ImagesViewerPage extends HookConsumerWidget {
  const ImagesViewerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mod = ref.watch(selectedModProvider);

    final existingImages = useMemoized(
        () => mod == null
            ? <Asset>[]
            : mod
                .getAssetsByType(AssetTypeEnum.image)
                .where((element) =>
                    element.fileExists &&
                    element.filePath != null &&
                    element.filePath!.isNotEmpty)
                .toList(),
        [mod]);

    final totalImagesCount =
        useMemoized(() => mod?.assetLists.images.length ?? 0, [mod]);

    return SafeArea(
      child: Scaffold(
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
                  mod?.saveName ?? '',
                  style: TextStyle(
                    overflow: TextOverflow.ellipsis,
                    fontSize: 30,
                  ),
                ),
              ),
              CustomTooltip(
                message:
                    '• Double-click to open image file\n• Left/Right-click to see options',
                child: Icon(Icons.info_outline, size: 30),
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
                if (mod == null) {
                  return SizedBox.shrink();
                }

                return ImagesViewerGridCard(asset: existingImages[index]);
              },
            );
          },
        ),
      ),
    );
  }
}
