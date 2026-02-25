import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider, backupSortAndFilterProvider;
import 'package:tts_mod_vault/src/state/sort_and_filter/backup_sort_and_filter_state.dart'
    show BackupMatchStatusEnum;

class BackupFilterButton extends HookConsumerWidget {
  const BackupFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final backupSortAndFilterState = ref.watch(backupSortAndFilterProvider);
    final backupSortAndFilterNotifier =
        ref.read(backupSortAndFilterProvider.notifier);

    final folders = useMemoized(() {
      return backupSortAndFilterState.backupFolders;
    }, [backupSortAndFilterState]);

    final selectedFolders = useMemoized(() {
      return backupSortAndFilterState.filteredBackupFolders;
    }, [backupSortAndFilterState]);

    final selectedMatchStatuses = useMemoized(() {
      return backupSortAndFilterState.filteredMatchStatuses;
    }, [backupSortAndFilterState]);

    final totalFilters = useMemoized(() {
      return selectedFolders.length + selectedMatchStatuses.length;
    }, [selectedFolders, selectedMatchStatuses]);

    final filtersText = useMemoized(() {
      return totalFilters > 0 ? 'Filters ($totalFilters)' : 'Filters';
    }, [totalFilters]);

    return SizedBox(
      height: 32,
      child: MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(Colors.white),
        ),
        builder: (context, controller, child) {
          return ElevatedButton.icon(
            label: Text(filtersText),
            onPressed: () {
              if (actionInProgress) return;

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
            icon: const Icon(Icons.filter_list, size: 20),
          );
        },
        menuChildren: [
          MenuItemButton(
            closeOnActivate: true,
            style: MenuItemButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              iconColor: Colors.black,
            ),
            onPressed: () {
              backupSortAndFilterNotifier.clearFilteredFolders();
              backupSortAndFilterNotifier.clearFilteredMatchStatuses();
            },
            child: Row(
              spacing: 8,
              children: [
                Icon(Icons.clear),
                Expanded(
                  child: Text(
                    'Clear all',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.black),
          if (folders.isNotEmpty)
            SubmenuButton(
              leadingIcon: Icon(
                Icons.check,
                color: selectedFolders.isNotEmpty
                    ? Colors.black
                    : Colors.transparent,
              ),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.white),
                foregroundColor: WidgetStateProperty.all(Colors.black),
                iconColor: WidgetStateProperty.all(Colors.black),
              ),
              menuStyle: MenuStyle(
                backgroundColor: WidgetStateProperty.all(Colors.white),
              ),
              menuChildren: [
                MenuItemButton(
                  closeOnActivate: false,
                  style: MenuItemButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    iconColor: Colors.black,
                  ),
                  onPressed: () =>
                      backupSortAndFilterNotifier.clearFilteredFolders(),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(Icons.clear),
                      Expanded(
                        child: Text(
                          'Clear all',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.black),
                ...folders.map((folder) {
                  final isSelected = selectedFolders.contains(folder);

                  return MenuItemButton(
                    closeOnActivate: false,
                    style: MenuItemButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      iconColor: Colors.black,
                    ),
                    onPressed: () {
                      if (isSelected) {
                        backupSortAndFilterNotifier
                            .removeFilteredFolder(folder);
                      } else {
                        backupSortAndFilterNotifier.addFilteredFolder(folder);
                      }
                    },
                    child: Row(
                      spacing: 8,
                      children: [
                        Icon(isSelected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank),
                        Expanded(
                          child: Text(
                            folder,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              child: SizedBox(
                width: 110,
                child: Text(
                  selectedFolders.isEmpty
                      ? 'Folders'
                      : 'Folders (${selectedFolders.length})',
                ),
              ),
            ),
          SubmenuButton(
            leadingIcon: Icon(
              Icons.check,
              color: selectedMatchStatuses.isNotEmpty
                  ? Colors.black
                  : Colors.transparent,
            ),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.white),
              foregroundColor: WidgetStateProperty.all(Colors.black),
              iconColor: WidgetStateProperty.all(Colors.black),
            ),
            menuStyle: MenuStyle(
              backgroundColor: WidgetStateProperty.all(Colors.white),
            ),
            menuChildren: [
              MenuItemButton(
                closeOnActivate: false,
                style: MenuItemButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  iconColor: Colors.black,
                ),
                onPressed: () =>
                    backupSortAndFilterNotifier.clearFilteredMatchStatuses(),
                child: Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.clear),
                    Expanded(
                      child: Text(
                        'Clear all',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.black),
              ...BackupMatchStatusEnum.values.map((status) {
                final isSelected = selectedMatchStatuses.contains(status);

                return MenuItemButton(
                  closeOnActivate: false,
                  style: MenuItemButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    iconColor: Colors.black,
                  ),
                  onPressed: () {
                    if (isSelected) {
                      backupSortAndFilterNotifier
                          .removeFilteredMatchStatus(status);
                    } else {
                      backupSortAndFilterNotifier
                          .addFilteredMatchStatus(status);
                    }
                  },
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(isSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank),
                      Expanded(
                        child: Text(
                          status.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            child: SizedBox(
              width: 110,
              child: Text(
                selectedMatchStatuses.isEmpty
                    ? 'Matching mod'
                    : 'Matching mod (${selectedMatchStatuses.length})',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
