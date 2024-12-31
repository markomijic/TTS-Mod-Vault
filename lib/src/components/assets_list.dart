import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/components/assets_action_buttons.dart';
import 'package:tts_mod_vault/src/components/assets_list_section.dart';
import 'package:tts_mod_vault/src/components/progress_bar.dart';
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/provider.dart';

class AssetsList extends HookConsumerWidget {
  const AssetsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(modsProvider).selectedMod;
    final isDownloading = ref.watch(downloadProvider).isDownloading;

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
          child: Text(
            selectedMod != null ? selectedMod.name : 'Select a mod',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
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
                      type: AssetType.assetBundle,
                      assets: selectedMod.assetLists!.assetBundles,
                    ),

                  // Audio Column
                  if (selectedMod.assetLists!.audio.isNotEmpty)
                    AssetsListSection(
                      type: AssetType.audio,
                      assets: selectedMod.assetLists!.audio,
                    ),

                  // Images Column
                  if (selectedMod.assetLists!.images.isNotEmpty)
                    AssetsListSection(
                      type: AssetType.image,
                      assets: selectedMod.assetLists!.images,
                    ),

                  // Models Column
                  if (selectedMod.assetLists!.models.isNotEmpty)
                    AssetsListSection(
                      type: AssetType.model,
                      assets: selectedMod.assetLists!.models,
                    ),

                  // PDF Column
                  if (selectedMod.assetLists!.pdf.isNotEmpty)
                    AssetsListSection(
                      type: AssetType.pdf,
                      assets: selectedMod.assetLists!.pdf,
                    ),
                ],
              ),
            ),
          ),
        if (selectedMod != null)
          SizedBox(
            height: 80,
            child: isDownloading ? ProgressBar() : AssetsActionButtons(),
          ),
      ],
    );
  }
}
