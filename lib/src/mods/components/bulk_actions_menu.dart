import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;

import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        modsSearchQueryProvider,
        selectedModTypeProvider,
        sortAndFilterProvider;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show BulkBackupDialog, showUpdateUrlsDialog;
import 'package:tts_mod_vault/src/utils.dart'
    show showConfirmDialogWithCheckbox;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkBackupBehaviorEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider, bulkActionsProvider, filteredModsProvider;

class BulkActionsMenu extends HookConsumerWidget {
  const BulkActionsMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final selectedModType = ref.watch(selectedModTypeProvider);
    final sortAndFilterState = ref.watch(sortAndFilterProvider);
    final searchQuery = ref.watch(modsSearchQueryProvider);

    final selectedFolders = useMemoized(() {
      Set<String> selectedFolders = switch (selectedModType) {
        ModTypeEnum.mod => sortAndFilterState.filteredModsFolders,
        ModTypeEnum.save => sortAndFilterState.filteredSavesFolders,
        ModTypeEnum.savedObject =>
          sortAndFilterState.filteredSavedObjectsFolders,
      };

      return selectedFolders;
    }, [selectedModType, sortAndFilterState]);

    final bulkActionLimited = useMemoized(() {
      return ((selectedFolders.length +
                  sortAndFilterState.filteredBackupStatuses.length) >
              0) ||
          searchQuery.isNotEmpty;
    }, [selectedFolders, sortAndFilterState, searchQuery]);

    return CustomTooltip(
      message: bulkActionLimited
          ? 'Bulk actions will apply only to the current selection because of the applied search/filters'
          : '',
      waitDuration: Duration(milliseconds: 750),
      child: Badge(
        backgroundColor: Colors.grey,
        textColor: Colors.white,
        smallSize: 12,
        isLabelVisible: bulkActionLimited && !actionInProgress,
        child: _BulkActionsDropDownButton(),
      ),
    );
  }
}

class _BulkActionsDropDownButton extends HookConsumerWidget {
  const _BulkActionsDropDownButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final selectedModType = ref.watch(selectedModTypeProvider);

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.white),
      ),
      menuChildren: <Widget>[
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.download, color: Colors.black),
          child: Text('Download all', style: TextStyle(color: Colors.black)),
          onPressed: () {
            if (actionInProgress) return;

            ref
                .read(bulkActionsProvider.notifier)
                .downloadAllMods(ref.read(filteredModsProvider));
          },
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.archive, color: Colors.black),
          child: Text('Backup all', style: TextStyle(color: Colors.black)),
          onPressed: () {
            if (actionInProgress) return;

            showDialog(
              context: context,
              builder: (context) => BulkBackupDialog(
                title: 'Backup all',
                initialBehavior: BulkBackupBehaviorEnum.replaceIfOutOfDate,
                onConfirm: (behavior, folder) {
                  ref.read(bulkActionsProvider.notifier).backupAllMods(
                        ref.read(filteredModsProvider),
                        behavior,
                        folder,
                      );
                },
              ),
            );
          },
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.download, color: Colors.black),
          trailingIcon: Icon(Icons.archive, color: Colors.black),
          child: Text('Download & backup all',
              style: TextStyle(color: Colors.black)),
          onPressed: () {
            if (actionInProgress) return;

            showDialog(
              context: context,
              builder: (context) => BulkBackupDialog(
                title: 'Download & backup all',
                initialBehavior: BulkBackupBehaviorEnum.replaceIfOutOfDate,
                onConfirm: (behavior, folder) {
                  ref
                      .read(bulkActionsProvider.notifier)
                      .downloadAndBackupAllMods(
                        ref.read(filteredModsProvider),
                        behavior,
                        folder,
                      );
                },
              ),
            );
          },
        ),
        Divider(color: Colors.black, height: 1),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          leadingIcon: Icon(Icons.edit, color: Colors.black),
          child: Text('Update all URLs', style: TextStyle(color: Colors.black)),
          onPressed: () {
            if (actionInProgress) return;

            showUpdateUrlsDialog(
              context,
              ref,
              onConfirm: (oldUrlPrefix, newUrlPrefix, renameFile) {
                ref.read(bulkActionsProvider.notifier).updateUrlPrefixesAllMods(
                      ref.read(filteredModsProvider),
                      oldUrlPrefix.split('|'),
                      newUrlPrefix,
                      renameFile,
                    );
              },
            );
          },
        ),
        if (selectedModType == ModTypeEnum.mod)
          MenuItemButton(
            style: MenuItemButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            leadingIcon: Icon(Icons.update, color: Colors.black),
            child:
                Text('Update all mods', style: TextStyle(color: Colors.black)),
            onPressed: () {
              if (actionInProgress) return;

              showConfirmDialogWithCheckbox(
                context,
                title: 'Update all mods',
                message:
                    'Check for updates and download newer versions from Steam Workshop',
                checkboxLabel: 'Force update',
                checkboxInfoMessage:
                    'Re-download all mods even if already up to date',
                showWarning: true,
                warningText:
                    "This feature has been tested with various mods, however it's recommended to let Tabletop Simulator handle updates directly to avoid unexpected issues.",
                onConfirm: (forceUpdate) {
                  ref.read(bulkActionsProvider.notifier).updateModsAll(
                        ref.read(filteredModsProvider),
                        forceUpdate,
                        context,
                      );
                },
              );
            },
          ),
      ],
      builder: (
        BuildContext context,
        MenuController controller,
        Widget? child,
      ) {
        return ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
          label: Text('Bulk actions'),
          icon: Icon(
            Icons.arrow_drop_down,
            size: 26,
          ),
        );
      },
    );
  }
}
