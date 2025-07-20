import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect, useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        selectedModTypeProvider,
        settingsProvider,
        sortAndFilterProvider;

class FilterButton extends HookConsumerWidget {
  const FilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showBackupState = ref.watch(settingsProvider).showBackupState;
    final actionInProgress = ref.watch(actionInProgressProvider);
    final selectedModType = ref.watch(selectedModTypeProvider);
    final sortAndFilterState = ref.watch(sortAndFilterProvider);
    final sortAndFilterNotifier = ref.read(sortAndFilterProvider.notifier);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!showBackupState &&
            sortAndFilterState.filteredBackupStatuses.isNotEmpty) {
          sortAndFilterNotifier.clearFilteredBackupStatuses();
        }
      });

      return null;
    }, [showBackupState]);

    final folders = useMemoized(() {
      Set<String> folders = switch (selectedModType) {
        ModTypeEnum.mod => sortAndFilterState.modsFolders,
        ModTypeEnum.save => sortAndFilterState.savesFolders,
        ModTypeEnum.savedObject => sortAndFilterState.savedObjectsFolders,
      };

      return folders;
    }, [selectedModType]);

    final selectedFolders = useMemoized(() {
      Set<String> selectedFolders = switch (selectedModType) {
        ModTypeEnum.mod => sortAndFilterState.filteredModsFolders,
        ModTypeEnum.save => sortAndFilterState.filteredSavesFolders,
        ModTypeEnum.savedObject =>
          sortAndFilterState.filteredSavedObjectsFolders,
      };

      return selectedFolders;
    }, [selectedModType, sortAndFilterState]);

    final totalFilters = useMemoized(() {
      return selectedFolders.length +
          sortAndFilterState.filteredBackupStatuses.length;
    }, [selectedFolders, sortAndFilterState]);

    return MenuAnchor(
      builder: (context, controller, child) {
        return IconButton(
          alignment: Alignment.center,
          onPressed: () {
            if (actionInProgress) return;

            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          style: ButtonStyle(
            backgroundColor:
                WidgetStateProperty.all(Colors.white), // Background
            foregroundColor: WidgetStateProperty.all(Colors.black), // Icon
          ),
          icon: Badge(
            backgroundColor: Colors.black,
            textColor: Colors.white,
            isLabelVisible: totalFilters > 0,
            label: Text('$totalFilters'),
            child: const Icon(
              Icons.filter_list,
              size: 20,
            ),
          ),
        );
      },
      menuChildren: [
        // Main "Clear all filters" item
        MenuItemButton(
          closeOnActivate: true,
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            iconColor: Colors.black,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Clear all",
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.clear),
            ],
          ),
          onPressed: () {
            sortAndFilterNotifier.clearFilteredBackupStatuses();
            sortAndFilterNotifier.clearFilteredFolders(selectedModType);
          },
        ),

        // Main "Folders" submenu item
        SubmenuButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            iconColor: Colors.black,
          ),
          menuChildren: [
            // "Clear all" option
            MenuItemButton(
              closeOnActivate: false,
              style: MenuItemButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                iconColor: Colors.black,
              ),
              child: Row(
                spacing: 8,
                children: [
                  Icon(Icons.clear),
                  Expanded(
                    child: Text(
                      "Clear all",
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              onPressed: () {
                sortAndFilterNotifier.clearFilteredFolders(selectedModType);
              },
            ),

            // Divider between "Clear all" and individual folders
            if (folders.isNotEmpty)
              const Divider(height: 1, color: Colors.black),

            // Individual folder options
            ...folders.map((folder) {
              final isSelected = selectedFolders.contains(folder);

              return MenuItemButton(
                closeOnActivate: false,
                style: MenuItemButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  iconColor: Colors.black,
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                    ),
                    Expanded(
                      child: Text(
                        folder,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                onPressed: () {
                  if (isSelected) {
                    sortAndFilterNotifier.removeFilteredFolder(
                        folder, selectedModType);
                  } else {
                    sortAndFilterNotifier.addFilteredFolder(
                        folder, selectedModType);
                  }
                },
              );
            }),

            // Show message if no folders available
            if (folders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No folders available'),
              ),
          ],
          child: SizedBox(
            width: 80,
            child: Text(
              selectedFolders.isEmpty
                  ? 'Folders'
                  : 'Folders (${selectedFolders.length})',
            ),
          ),
        ),

        // Main "Backups" submenu item
        if (showBackupState)
          SubmenuButton(
            style: MenuItemButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              iconColor: Colors.black,
            ),
            menuChildren: [
              // "Clear all" option
              MenuItemButton(
                closeOnActivate: false,
                style: MenuItemButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  iconColor: Colors.black,
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.clear),
                    Expanded(
                      child: Text(
                        "Clear all",
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                onPressed: () {
                  sortAndFilterNotifier.clearFilteredBackupStatuses();
                },
              ),

              // Divider between "Clear all" and backup status options
              const Divider(height: 1, color: Colors.black),

              // Generate backup status options dynamically from enum
              ...ExistingBackupStatusEnum.values.map((status) {
                final isSelected =
                    sortAndFilterState.filteredBackupStatuses.contains(status);

                return MenuItemButton(
                  closeOnActivate: false,
                  style: MenuItemButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    iconColor: Colors.black,
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                      ),
                      Expanded(
                        child: Text(
                          status.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  onPressed: () {
                    if (isSelected) {
                      sortAndFilterNotifier.removeFilteredBackupStatus(status);
                    } else {
                      sortAndFilterNotifier.addFilteredBackupStatus(status);
                    }
                  },
                );
              }),
            ],
            child: SizedBox(
              width: 80,
              child: Text(
                sortAndFilterState.filteredBackupStatuses.isEmpty
                    ? 'Backups'
                    : 'Backups (${sortAndFilterState.filteredBackupStatuses.length})',
              ),
            ),
          ),
      ],
    );
  }
}
