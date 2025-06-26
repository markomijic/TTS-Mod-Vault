import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show SelectedModActionButtons, AssetsUrl, DownloadProgressBar, HelpTooltip;
import 'package:tts_mod_vault/src/mods/components/custom_tooltip.dart'
    show CustomTooltip;

import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        downloadProvider,
        modsProvider,
        selectedModProvider,
        selectedModTypeProvider;
import 'package:tts_mod_vault/src/utils.dart' show openUrl;

abstract class _ListItem {}

class _HeaderItem extends _ListItem {
  final AssetTypeEnum type;
  final List<Asset> assets;
  final bool hasMissingFiles;

  _HeaderItem({
    required this.type,
    required this.assets,
    required this.hasMissingFiles,
  });
}

class _AssetItem extends _ListItem {
  final Asset asset;
  final AssetTypeEnum type;

  _AssetItem({
    required this.asset,
    required this.type,
  });
}

class SelectedModView extends HookConsumerWidget {
  const SelectedModView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(selectedModProvider);
    final selectedModType = ref.watch(selectedModTypeProvider);

    if (selectedMod == null) {
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
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    "Select a ${selectedModType.label}",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: HelpTooltip(),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _SelectedModViewComponent(selectedMod: selectedMod);
  }
}

class _SelectedModViewComponent extends HookConsumerWidget {
  final Mod selectedMod;

  const _SelectedModViewComponent({
    required this.selectedMod,
  });

  List<_ListItem> _buildListItems() {
    final List<_ListItem> items = [];

    for (final type in AssetTypeEnum.values) {
      final assets = selectedMod.getAssetsByType(type);

      if (assets.isNotEmpty) {
        // Add header
        items.add(
          _HeaderItem(
            type: type,
            assets: assets,
            hasMissingFiles: assets.any((e) => !e.fileExists),
          ),
        );

        // Add all assets for this type
        for (final asset in assets) {
          items.add(_AssetItem(asset: asset, type: type));
        }
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadProvider);

    final listItems = useMemoized(() => _buildListItems(), [selectedMod]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          padding: EdgeInsets.only(top: 8),
          child: Row(
            spacing: 8,
            children: [
              if (selectedMod.modType == ModTypeEnum.mod)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => openUrl(
                        "https://steamcommunity.com/sharedfiles/filedetails/?id=${selectedMod.jsonFileName}"),
                    child: CustomTooltip(
                      message: 'Open on Steam Workshop',
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        padding: EdgeInsets.all(2),
                        child: Image.asset(
                          'assets/icon/steam_logo.png',
                          height: 22,
                          isAntiAlias: true,
                          fit: BoxFit.fitHeight,
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  selectedMod.modType == ModTypeEnum.mod
                      ? selectedMod.saveName
                      : '${selectedMod.jsonFileName}\n${selectedMod.saveName}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: HelpTooltip(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: ValueKey(selectedMod.jsonFileName),
            itemCount: listItems.length,
            itemBuilder: (context, index) {
              final item = listItems[index];

              if (item is _HeaderItem) {
                return _buildHeader(context, ref, item, selectedMod);
              } else if (item is _AssetItem) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: AssetsUrl(asset: item.asset, type: item.type),
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ),
        SizedBox(
          height: 80,
          child: downloadState.cancelledDownloads || downloadState.isDownloading
              ? DownloadProgressBar()
              : listItems.isNotEmpty
                  ? SelectedModActionButtons(selectedMod: selectedMod)
                  : null,
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    _HeaderItem headerItem,
    Mod selectedMod,
  ) {
    final actionInProgress = ref.watch(actionInProgressProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
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
              headerItem.type.label,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (headerItem.hasMissingFiles && !actionInProgress)
              _MissingFilesButton(
                ref: ref,
                assetType: headerItem.type,
                selectedMod: selectedMod,
              ),
            if (headerItem.type == AssetTypeEnum.image && !actionInProgress)
              _OpenImagesViewerButton(selectedMod: selectedMod)
          ],
        ),
      ),
    );
  }
}

class _OpenImagesViewerButton extends StatelessWidget {
  final Mod selectedMod;

  const _OpenImagesViewerButton({required this.selectedMod});

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: "View Images",
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () async {
            if (context.mounted) {
              Navigator.of(context).pushNamed('/images-viewer');
            }
          },
          child: Icon(Icons.image, size: 20),
        ),
      ),
    );
  }
}

class _MissingFilesButton extends StatelessWidget {
  final WidgetRef ref;
  final AssetTypeEnum assetType;
  final Mod selectedMod;

  const _MissingFilesButton({
    required this.ref,
    required this.assetType,
    required this.selectedMod,
  });

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: "Download all missing ${assetType.label.toLowerCase()}",
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () async {
            final urls = selectedMod
                .getAssetsByType(assetType)
                .map((e) => e.fileExists ? null : e.url)
                .nonNulls
                .toList();

            await ref.read(downloadProvider.notifier).downloadFiles(
                  modAssetListUrls: urls,
                  type: assetType,
                  downloadingAllFiles: false,
                );

            await ref.read(modsProvider.notifier).updateMod(selectedMod);
          },
          child: Icon(Icons.download, size: 20),
        ),
      ),
    );
  }
}
