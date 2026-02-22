import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show
        useEffect,
        useFocusNode,
        useMemoized,
        useState,
        useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show
        SelectedModActionButtons,
        AssetsUrl,
        DownloadProgressBar,
        HelpTooltip,
        CustomTooltip,
        BackupProgressBar,
        MultiSelectView;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupStatusEnum;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show AudioAssetVisibility, Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        backupProvider,
        downloadProvider,
        modsProvider,
        multiModsProvider,
        selectedModProvider,
        selectedModTypeProvider,
        settingsProvider,
        storageProvider;

enum ExistingAssetsFilter {
  all('All'),
  missingOnly('Missing'),
  downloadedOnly('Downloaded');

  final String label;
  const ExistingAssetsFilter(this.label);
}

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
    final multiSelectMods = ref.watch(multiModsProvider);

    // Show multi-select view when 2+ mods selected
    if (multiSelectMods.length >= 2) {
      return const MultiSelectView();
    }

    // Show "Select a mod" message when nothing is selected
    if (selectedMod == null) {
      return Column(
        children: [
          Container(
            alignment: Alignment.topLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white, width: 2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                  child: HelpTooltip(),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Show single mod view
    return _SelectedModViewComponent(selectedMod: selectedMod);
  }
}

class _SelectedModViewComponent extends HookConsumerWidget {
  final Mod selectedMod;

  const _SelectedModViewComponent({required this.selectedMod});

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
    final selectedAssetTypeFilter = useState<AssetTypeEnum?>(null);
    final downloadFilter = useState(ExistingAssetsFilter.all);
    final isSearchActive = useState(false);
    final searchQuery = useState('');
    final searchController = useTextEditingController();
    final searchFocusNode = useFocusNode();

    useEffect(() {
      void onFocusChange() {
        if (!searchFocusNode.hasFocus && searchController.text.isEmpty) {
          isSearchActive.value = false;
        }
      }

      searchFocusNode.addListener(onFocusChange);
      return () => searchFocusNode.removeListener(onFocusChange);
    }, []);

    final downloadState = ref.watch(downloadProvider);
    final backupStatus = ref.watch(backupProvider).status;

    final listItems = useMemoized(() => _buildListItems(), [selectedMod]);
    final availableAssetTypes = useMemoized(() {
      return AssetTypeEnum.values.where((type) {
        return selectedMod.getAssetsByType(type).isNotEmpty;
      }).toList();
    }, [selectedMod]);

    useMemoized(() {
      selectedAssetTypeFilter.value = null;
    }, [selectedMod]);

    useEffect(() {
      isSearchActive.value = false;
      searchQuery.value = '';
      searchController.clear();
      return null;
    }, [selectedMod.jsonFileName]);

    final title = useMemoized(() {
      return switch (selectedMod.modType) {
        ModTypeEnum.mod => selectedMod.saveName,
        ModTypeEnum.save =>
          '${selectedMod.jsonFileName}\n${selectedMod.saveName}',
        ModTypeEnum.savedObject => selectedMod.saveName,
      };
    }, [selectedMod]);

    final typesWithVisibleAssets = useMemoized(() {
      if (searchQuery.value.isEmpty) return null;
      return listItems
          .whereType<_AssetItem>()
          .where((item) => item.asset.url
              .toLowerCase()
              .contains(searchQuery.value.toLowerCase()))
          .map((item) => item.type)
          .toSet();
    }, [listItems, searchQuery.value]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white, width: 2),
            ),
          ),
          alignment: Alignment.topLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: HelpTooltip(),
              ),
            ],
          ),
        ),
        Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              MenuAnchor(
                style: MenuStyle(
                  backgroundColor: WidgetStateProperty.all(Colors.white),
                ),
                builder: (context, controller, child) {
                  return ElevatedButton.icon(
                    onPressed: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(Colors.white),
                      foregroundColor: WidgetStateProperty.all(Colors.black),
                    ),
                    icon: Icon(Icons.arrow_drop_down, size: 26),
                    label: Text(downloadFilter.value.label),
                  );
                },
                menuChildren: [
                  ...ExistingAssetsFilter.values.map((filter) {
                    final isSelected = downloadFilter.value == filter;
                    return MenuItemButton(
                      closeOnActivate: true,
                      style: MenuItemButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        iconColor: Colors.black,
                      ),
                      child: Row(
                        spacing: 8,
                        children: [
                          Icon(isSelected ? Icons.check : null),
                          Expanded(
                            child: Text(
                              filter.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      onPressed: () => downloadFilter.value = filter,
                    );
                  }),
                ],
              ),
              if (selectedMod.hasAudioAssets) ...[
                _AudioAssetsButton(selectedMod: selectedMod),
              ],
              isSearchActive.value
                  ? SizedBox(
                      width: 300,
                      height: 32,
                      child: TextField(
                        controller: searchController,
                        focusNode: searchFocusNode,
                        autofocus: true,
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 20),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.black,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: Colors.black,
                              size: 17,
                            ),
                            onPressed: () {
                              searchController.clear();
                              searchQuery.value = '';
                              isSearchActive.value = false;
                            },
                          ),
                          hintText: 'Search',
                          hintStyle: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) => searchQuery.value = value,
                      ),
                    )
                  : SizedBox(
                      height: 32,
                      width: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          isSearchActive.value = true;
                          searchFocusNode.requestFocus();
                        },
                        style: ButtonStyle(
                          backgroundColor:
                              WidgetStateProperty.all(Colors.white),
                          foregroundColor:
                              WidgetStateProperty.all(Colors.black),
                          padding: WidgetStateProperty.all(EdgeInsets.zero),
                          shape: WidgetStateProperty.all(
                            CircleBorder(),
                          ),
                        ),
                        child: Icon(Icons.search, size: 20),
                      ),
                    ),
              ...availableAssetTypes.map((type) {
                return FilterChip(
                  showCheckmark: false,
                  label: Text(type.label),
                  selected: selectedAssetTypeFilter.value == type,
                  onSelected: (selected) {
                    selectedAssetTypeFilter.value = selected ? type : null;
                  },
                  selectedColor: Colors.white,
                  checkmarkColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                );
              }),
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
                // Filter by selected asset type - hide header if not matching
                if (selectedAssetTypeFilter.value != null &&
                    item.type != selectedAssetTypeFilter.value) {
                  return const SizedBox.shrink();
                }

                // Hide header if search is active and no assets match
                if (typesWithVisibleAssets != null &&
                    !typesWithVisibleAssets.contains(item.type)) {
                  return const SizedBox.shrink();
                }

                // Check if this is the first visible header
                final isFirstHeader = !listItems.take(index).any((prevItem) {
                  if (prevItem is! _HeaderItem) return false;
                  if (selectedAssetTypeFilter.value != null &&
                      prevItem.type != selectedAssetTypeFilter.value) {
                    return false;
                  }
                  if (typesWithVisibleAssets != null &&
                      !typesWithVisibleAssets.contains(prevItem.type)) {
                    return false;
                  }
                  return true;
                });

                return _buildHeader(
                    context, ref, item, selectedMod, isFirstHeader);
              } else if (item is _AssetItem) {
                // Filter by selected asset type
                if (selectedAssetTypeFilter.value != null &&
                    item.type != selectedAssetTypeFilter.value) {
                  return const SizedBox.shrink();
                }

                // Filter by download status
                if (downloadFilter.value == ExistingAssetsFilter.missingOnly &&
                    item.asset.fileExists) {
                  return const SizedBox.shrink();
                }
                if (downloadFilter.value ==
                        ExistingAssetsFilter.downloadedOnly &&
                    !item.asset.fileExists) {
                  return const SizedBox.shrink();
                }

                // Filter by search query
                if (searchQuery.value.isNotEmpty &&
                    !item.asset.url
                        .toLowerCase()
                        .contains(searchQuery.value.toLowerCase())) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: AssetsUrl(asset: item.asset, type: item.type),
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ),
        downloadState.isDownloading || downloadState.cancelledDownloads
            ? DownloadProgressBar()
            : backupStatus != BackupStatusEnum.idle
                ? BackupProgressBar()
                : listItems.isNotEmpty
                    ? SelectedModActionButtons(selectedMod: selectedMod)
                    : const SizedBox.shrink()
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    _HeaderItem headerItem,
    Mod selectedMod,
    bool isFirstHeader,
  ) {
    final actionInProgress = ref.watch(actionInProgressProvider);

    return Padding(
      padding: EdgeInsets.only(top: isFirstHeader ? 0.0 : 8.0),
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

class _AudioAssetsButton extends ConsumerWidget {
  final Mod selectedMod;

  const _AudioAssetsButton({required this.selectedMod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ignoreAudioAssets = ref.watch(settingsProvider).ignoreAudioAssets;
    final actionInProgress = ref.watch(actionInProgressProvider);

    return CustomTooltip(
      message: switch (selectedMod.audioVisibility) {
        AudioAssetVisibility.useGlobalSetting =>
          'Using global setting (${ignoreAudioAssets ? "hidden" : "shown"})',
        AudioAssetVisibility.alwaysShow => 'Override: Show audio assets',
        AudioAssetVisibility.alwaysHide => 'Override: Hide audio assets',
      },
      child: MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(Colors.white),
        ),
        builder: (context, controller, child) {
          final hasOverride = selectedMod.audioVisibility !=
              AudioAssetVisibility.useGlobalSetting;

          final showingAudio = switch (selectedMod.audioVisibility) {
            AudioAssetVisibility.alwaysShow => true,
            AudioAssetVisibility.alwaysHide => false,
            AudioAssetVisibility.useGlobalSetting => !ignoreAudioAssets,
          };

          return IconButton(
            onPressed: actionInProgress
                ? null
                : () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(
                hasOverride ? Colors.blue : Colors.white,
              ),
              foregroundColor: WidgetStateProperty.all(
                hasOverride ? Colors.white : Colors.black,
              ),
            ),
            padding: EdgeInsets.zero, // removes default padding
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            icon: Icon(
              showingAudio ? Icons.volume_up : Icons.volume_off,
            ),
          );
        },
        menuChildren: [
          MenuItemButton(
            closeOnActivate: true,
            style: MenuItemButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  selectedMod.audioVisibility ==
                          AudioAssetVisibility.useGlobalSetting
                      ? Icons.check
                      : null,
                  color: Colors.black,
                ),
                Icon(Icons.settings, color: Colors.black),
                Text('Use global setting'),
              ],
            ),
            onPressed: () async {
              if (selectedMod.audioVisibility !=
                  AudioAssetVisibility.useGlobalSetting) {
                final updatedMod = Mod(
                  modType: selectedMod.modType,
                  jsonFilePath: selectedMod.jsonFilePath,
                  jsonFileName: selectedMod.jsonFileName,
                  parentFolderName: selectedMod.parentFolderName,
                  saveName: selectedMod.saveName,
                  createdAtTimestamp: selectedMod.createdAtTimestamp,
                  lastModifiedTimestamp: selectedMod.lastModifiedTimestamp,
                  dateTimeStamp: selectedMod.dateTimeStamp,
                  imageFilePath: selectedMod.imageFilePath,
                  backup: selectedMod.backup,
                  backupStatus: selectedMod.backupStatus,
                  assetLists: selectedMod.assetLists,
                  assetCount: selectedMod.assetCount,
                  existingAssetCount: selectedMod.existingAssetCount,
                  hasAudioAssets: selectedMod.hasAudioAssets,
                  // -----------------------------------------
                  audioVisibility: AudioAssetVisibility.useGlobalSetting,
                );

                await ref.read(storageProvider).setModAudioPreference(
                      selectedMod.jsonFileName,
                      AudioAssetVisibility.useGlobalSetting,
                    );
                await ref
                    .read(modsProvider.notifier)
                    .reprocessModAssets(updatedMod);
              }
            },
          ),
          MenuItemButton(
            closeOnActivate: true,
            style: MenuItemButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  selectedMod.audioVisibility == AudioAssetVisibility.alwaysShow
                      ? Icons.check
                      : null,
                  color: Colors.black,
                ),
                Icon(Icons.volume_up, color: Colors.black),
                Text('Show audio'),
              ],
            ),
            onPressed: () async {
              if (selectedMod.audioVisibility !=
                  AudioAssetVisibility.alwaysShow) {
                final updatedMod = Mod(
                  modType: selectedMod.modType,
                  jsonFilePath: selectedMod.jsonFilePath,
                  jsonFileName: selectedMod.jsonFileName,
                  parentFolderName: selectedMod.parentFolderName,
                  saveName: selectedMod.saveName,
                  createdAtTimestamp: selectedMod.createdAtTimestamp,
                  lastModifiedTimestamp: selectedMod.lastModifiedTimestamp,
                  dateTimeStamp: selectedMod.dateTimeStamp,
                  imageFilePath: selectedMod.imageFilePath,
                  backup: selectedMod.backup,
                  backupStatus: selectedMod.backupStatus,
                  assetLists: selectedMod.assetLists,
                  assetCount: selectedMod.assetCount,
                  existingAssetCount: selectedMod.existingAssetCount,
                  hasAudioAssets: selectedMod.hasAudioAssets,
                  // -----------------------------------------
                  audioVisibility: AudioAssetVisibility.alwaysShow,
                );
                await ref.read(storageProvider).setModAudioPreference(
                      selectedMod.jsonFileName,
                      AudioAssetVisibility.alwaysShow,
                    );
                await ref
                    .read(modsProvider.notifier)
                    .reprocessModAssets(updatedMod);
              }
            },
          ),
          MenuItemButton(
            closeOnActivate: true,
            style: MenuItemButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  selectedMod.audioVisibility == AudioAssetVisibility.alwaysHide
                      ? Icons.check
                      : null,
                  color: Colors.black,
                ),
                Icon(Icons.volume_off, color: Colors.black),
                Text('Hide audio'),
              ],
            ),
            onPressed: () async {
              if (selectedMod.audioVisibility !=
                  AudioAssetVisibility.alwaysHide) {
                final updatedMod = Mod(
                  modType: selectedMod.modType,
                  jsonFilePath: selectedMod.jsonFilePath,
                  jsonFileName: selectedMod.jsonFileName,
                  parentFolderName: selectedMod.parentFolderName,
                  saveName: selectedMod.saveName,
                  createdAtTimestamp: selectedMod.createdAtTimestamp,
                  lastModifiedTimestamp: selectedMod.lastModifiedTimestamp,
                  dateTimeStamp: selectedMod.dateTimeStamp,
                  imageFilePath: selectedMod.imageFilePath,
                  backup: selectedMod.backup,
                  backupStatus: selectedMod.backupStatus,
                  assetLists: selectedMod.assetLists,
                  assetCount: selectedMod.assetCount,
                  existingAssetCount: selectedMod.existingAssetCount,
                  hasAudioAssets: selectedMod.hasAudioAssets,
                  // -----------------------------------------
                  audioVisibility: AudioAssetVisibility.alwaysHide,
                );

                await ref.read(storageProvider).setModAudioPreference(
                      selectedMod.jsonFileName,
                      AudioAssetVisibility.alwaysHide,
                    );
                await ref
                    .read(modsProvider.notifier)
                    .reprocessModAssets(updatedMod);
              }
            },
          ),
        ],
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

            final downloaded =
                await ref.read(downloadProvider.notifier).downloadFiles(
                      modAssetListUrls: urls,
                      type: assetType,
                      downloadingAllFiles: false,
                    );

            await ref
                .read(modsProvider.notifier)
                .updateSelectedMod(selectedMod);

            if (downloaded.isNotEmpty) {
              await ref.read(modsProvider.notifier).refreshModsWithSharedAssets(
                  downloaded.toSet(),
                  excludeJsonFileName: selectedMod.jsonFileName);
            }
          },
          child: Icon(Icons.download, size: 20),
        ),
      ),
    );
  }
}
