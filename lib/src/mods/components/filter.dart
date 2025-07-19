import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show sortAndFilterProvider;

class ModsFolderFilterMenu extends ConsumerWidget {
  const ModsFolderFilterMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortAndFilterState = ref.watch(sortAndFilterProvider);
    final sortAndFilterNotifier = ref.read(sortAndFilterProvider.notifier);

    return MenuAnchor(
      builder: (context, controller, child) {
        return IconButton(
          alignment: Alignment.center,
          onPressed: () {
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
            isLabelVisible: sortAndFilterState.filteredModsFolders.isNotEmpty,
            label: Text('${sortAndFilterState.filteredModsFolders.length}'),
            child: const Icon(
              Icons.filter_list,
              size: 20,
            ),
          ),
        );
      },
      menuChildren: [
        // Main "Folders" submenu item
        SubmenuButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            iconColor: Colors.black,
          ),
          menuChildren: [
            // "Select All" option
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
                sortAndFilterNotifier.clearFilteredModsFolders();
                /*       if (sortAndFilterState.filteredModsFolders.length ==
                    sortAndFilterState.modsFolders.length) {
                  // If all selected, clear all
                  sortAndFilterNotifier.clearFilteredModsFolders();
                } else {
                  // Otherwise select all
                  sortAndFilterNotifier.setFilteredModsFolders(
                    sortAndFilterState.modsFolders,
                  );
                } */
              },
            ),

            // Divider between "Select All" and individual folders
            if (sortAndFilterState.modsFolders.isNotEmpty)
              const Divider(height: 1, color: Colors.black),

            // Individual folder options
            ...sortAndFilterState.modsFolders.map((folder) {
              final isSelected =
                  sortAndFilterState.filteredModsFolders.contains(folder);

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
                    sortAndFilterNotifier.removeFilteredModFolder(folder);
                  } else {
                    sortAndFilterNotifier.addFilteredModFolder(folder);
                  }
                },
              );
            }),

            // Show message if no folders available
            if (sortAndFilterState.modsFolders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No folders available'),
              ),
          ],
          child: const Text('Folders'),
        ),
      ],
    );
  }
}
