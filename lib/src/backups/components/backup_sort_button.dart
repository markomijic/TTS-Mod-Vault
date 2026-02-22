import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider, backupSortAndFilterProvider;
import 'package:tts_mod_vault/src/state/sort_and_filter/backup_sort_and_filter_state.dart'
    show BackupSortOptionEnum;

class BackupSortButton extends HookConsumerWidget {
  const BackupSortButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final backupSortAndFilterState = ref.watch(backupSortAndFilterProvider);
    final backupSortAndFilterNotifier =
        ref.read(backupSortAndFilterProvider.notifier);

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.white),
      ),
      builder: (context, controller, child) {
        return ElevatedButton.icon(
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
          icon: const Icon(
            Icons.sort,
            size: 20,
          ),
          label: Text(
            backupSortAndFilterState.sortOption.label,
            textAlign: TextAlign.center,
          ),
        );
      },
      menuChildren: [
        ...BackupSortOptionEnum.values.map(
          (sortOption) {
            final isSelected =
                backupSortAndFilterState.sortOption == sortOption;

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
                      sortOption.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              onPressed: () =>
                  backupSortAndFilterNotifier.setSortOption(sortOption),
            );
          },
        ),
      ],
    );
  }
}
