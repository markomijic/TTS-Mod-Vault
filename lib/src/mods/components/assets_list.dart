import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/assets_action_buttons.dart'
    show AssetsActionButtons;
import 'package:tts_mod_vault/src/mods/components/assets_list_section.dart'
    show AssetsListSection;
import 'package:tts_mod_vault/src/mods/components/assets_tooltip.dart'
    show AssetsTooltip;
import 'package:tts_mod_vault/src/mods/components/progress_bar.dart'
    show DownloadProgressBar;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show downloadProvider, selectedModProvider;

class AssetsList extends HookConsumerWidget {
  const AssetsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(selectedModProvider);
    final isDownloading = ref.watch(downloadProvider).isDownloading;

    final selectedModHasAssets = useMemoized(
      () {
        if (selectedMod == null) {
          return false;
        }
        return selectedMod.getAllAssets().isNotEmpty;
      },
      [selectedMod],
    );

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white,
                width: 2.0,
              ),
            ),
          ),
          alignment: Alignment.topLeft,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  selectedMod != null ? selectedMod.name : 'Select a mod',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: AssetsTooltip(),
              ),
            ],
          ),
        ),
        if (selectedMod != null && selectedMod.assetLists != null)
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 8),

                  // Asset Bundles Column
                  if (selectedMod.assetLists!.assetBundles.isNotEmpty)
                    AssetsListSection(
                      type: AssetTypeEnum.assetBundle,
                      assets: selectedMod.assetLists!.assetBundles,
                    ),

                  // Audio Column
                  if (selectedMod.assetLists!.audio.isNotEmpty)
                    AssetsListSection(
                      type: AssetTypeEnum.audio,
                      assets: selectedMod.assetLists!.audio,
                    ),

                  // Images Column
                  if (selectedMod.assetLists!.images.isNotEmpty)
                    AssetsListSection(
                      type: AssetTypeEnum.image,
                      assets: selectedMod.assetLists!.images,
                    ),

                  // Models Column
                  if (selectedMod.assetLists!.models.isNotEmpty)
                    AssetsListSection(
                      type: AssetTypeEnum.model,
                      assets: selectedMod.assetLists!.models,
                    ),

                  // PDF Column
                  if (selectedMod.assetLists!.pdf.isNotEmpty)
                    AssetsListSection(
                      type: AssetTypeEnum.pdf,
                      assets: selectedMod.assetLists!.pdf,
                    ),
                ],
              ),
            ),
          ),
        if (selectedMod != null)
          SizedBox(
            height: 80,
            child: isDownloading
                ? DownloadProgressBar()
                : selectedModHasAssets
                    ? AssetsActionButtons()
                    : null,
          ),
      ],
    );
  }
}
