import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show BulkUpdateUrlsDialog;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkBackupBehaviorEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        bulkActionsProvider,
        multiSelectModsProvider,
        selectedModProvider,
        selectedModsListProvider,
        settingsProvider;

class MultiSelectView extends HookConsumerWidget {
  const MultiSelectView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMods = ref.watch(selectedModsListProvider);
    final actionInProgress = ref.watch(actionInProgressProvider);
    final settings = ref.watch(settingsProvider);

    // Check if all selected mods are of type 'mod' for Update Mods button
    final allModsAreMod =
        selectedMods.every((mod) => mod.modType == ModTypeEnum.mod);

    return Column(
      children: [
        // Header with count and clear button
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white,
                width: 2.0,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${selectedMods.length} Mods Selected',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.clear, size: 28),
                tooltip: 'Clear Selection',
                onPressed: actionInProgress
                    ? null
                    : () {
                        ref.read(multiSelectModsProvider.notifier).state = {};
                        ref.read(selectedModProvider.notifier).state = null;
                      },
              ),
            ],
          ),
        ),

        // Scrollable list of selected mod names
        Expanded(
          child: ListView.builder(
            itemCount: selectedMods.length,
            itemBuilder: (context, index) {
              final mod = selectedMods[index];
              return ListTile(
                leading: Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 20,
                ),
                title: Text(
                  mod.saveName,
                  style: const TextStyle(fontSize: 14),
                ),
                dense: true,
              );
            },
          ),
        ),

        // Action buttons section (fixed height: 80px)
        Container(
          height: 80,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.2),
                width: 1.0,
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download All'),
                  onPressed: actionInProgress
                      ? null
                      : () => _downloadAll(ref, selectedMods),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_zip, size: 18),
                  label: const Text('Backup All'),
                  onPressed: actionInProgress
                      ? null
                      : () => _backupAll(ref, selectedMods),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.backup, size: 18),
                  label: const Text('Download & Backup'),
                  onPressed: actionInProgress
                      ? null
                      : () => _downloadAndBackup(ref, selectedMods),
                ),
                if (settings.enableTtsModdersFeatures)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.update, size: 18),
                    label: const Text('Update URLs'),
                    onPressed: actionInProgress
                        ? null
                        : () => _updateUrls(context, ref, selectedMods),
                  ),
                if (allModsAreMod)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Update Mods'),
                    onPressed: actionInProgress
                        ? null
                        : () => _updateMods(ref, selectedMods),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _downloadAll(WidgetRef ref, List<Mod> selectedMods) {
    ref.read(bulkActionsProvider.notifier).downloadAllMods(selectedMods);
  }

  void _backupAll(WidgetRef ref, List<Mod> selectedMods) {
    // backupAllMods requires backupBehavior and folder parameters
    // Use replace behavior and let it prompt for folder
    ref
        .read(bulkActionsProvider.notifier)
        .backupAllMods(selectedMods, BulkBackupBehaviorEnum.replace, null);
  }

  void _downloadAndBackup(WidgetRef ref, List<Mod> selectedMods) {
    // downloadAndBackupAllMods requires backupBehavior and folder parameters
    ref
        .read(bulkActionsProvider.notifier)
        .downloadAndBackupAllMods(
            selectedMods, BulkBackupBehaviorEnum.replace, null);
  }

  void _updateUrls(BuildContext context, WidgetRef ref, List<Mod> selectedMods) {
    showDialog(
      context: context,
      builder: (context) => BulkUpdateUrlsDialog(
        onConfirm: (oldUrlPrefix, newUrlPrefix, renameFile) {
          // updateUrlPrefixesAllMods expects List<String> for oldPrefixes
          ref.read(bulkActionsProvider.notifier).updateUrlPrefixesAllMods(
                selectedMods,
                [oldUrlPrefix], // Wrap in list
                newUrlPrefix,
                renameFile,
              );
        },
      ),
    );
  }

  void _updateMods(WidgetRef ref, List<Mod> selectedMods) {
    // updateModsAll requires forceUpdate parameter
    ref
        .read(bulkActionsProvider.notifier)
        .updateModsAll(selectedMods, false);
  }
}
