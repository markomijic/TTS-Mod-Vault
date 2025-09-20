import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show HelpMenu, ToolsMenu, BulkActionsDropDownButton;
import 'package:tts_mod_vault/src/mods/components/custom_tooltip.dart';
import 'package:tts_mod_vault/src/settings/settings_dialog.dart'
    show SettingsDialog;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        importBackupProvider,
        loaderProvider,
        searchQueryProvider,
        selectedModTypeProvider,
        sortAndFilterProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showConfirmDialog, showSnackBar;

class Toolbar extends HookConsumerWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionInProgress = ref.watch(actionInProgressProvider);
    final importBackupNotifier = ref.watch(importBackupProvider.notifier);

    final searchQuery = ref.watch(searchQueryProvider);
    final selectedModType = ref.watch(selectedModTypeProvider);
    final sortAndFilterState = ref.watch(sortAndFilterProvider);

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

    return Row(
      spacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () => showDialog(
                    context: context,
                    builder: (context) => SettingsDialog(),
                  ),
          icon: const Icon(Icons.settings),
          label: const Text('Settings'),
        ),
        ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () => showConfirmDialog(
                    context,
                    'Are you sure you want to refresh data for all mods?',
                    () async {
                      await ref.read(loaderProvider).refreshAppData();
                    },
                  ),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
        ElevatedButton.icon(
          onPressed: actionInProgress
              ? null
              : () async {
                  final backupResult =
                      await importBackupNotifier.importBackup();

                  if (backupResult && context.mounted) {
                    showSnackBar(context, 'Import finished, refreshing data');
                    await ref.read(loaderProvider).refreshAppData();
                  }
                },
          icon: const Icon(Icons.unarchive),
          label: const Text('Import backup'),
        ),
        CustomTooltip(
          message: bulkActionLimited
              ? 'Bulk actions will apply only to the current selection because of the applied search/filters'
              : '',
          waitDuration: Duration(milliseconds: 750),
          child: Badge(
            backgroundColor: Colors.grey,
            textColor: Colors.white,
            smallSize: 12,
            isLabelVisible: bulkActionLimited && !actionInProgress,
            child: BulkActionsDropDownButton(),
          ),
        ),
        ToolsMenu(),
        HelpMenu(),
      ],
    );
  }
}
