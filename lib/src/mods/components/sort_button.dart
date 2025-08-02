import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider, sortAndFilterProvider;
import 'package:tts_mod_vault/src/state/sort_and_filter/sort_and_filter_state.dart'
    show SortOptionEnum;

class SortButton extends HookConsumerWidget {
  const SortButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final sortAndFilterState = ref.watch(sortAndFilterProvider);
    final sortAndFilterNotifier = ref.read(sortAndFilterProvider.notifier);

    return MenuAnchor(
      builder: (context, controller, child) {
        return ElevatedButton.icon(
          //alignment: Alignment.center,
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
          icon: Icon(
            Icons.sort,
            size: 20,
          ),
          label: Text(sortAndFilterState.sortOption.label),
        );
      },
      menuChildren: [
        ...SortOptionEnum.values.map(
          (sortOption) {
            final isSelected = sortAndFilterState.sortOption == sortOption;

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
              onPressed: () => sortAndFilterNotifier.setSortOption(sortOption),
            );
          },
        ),
      ],
    );
  }
}
