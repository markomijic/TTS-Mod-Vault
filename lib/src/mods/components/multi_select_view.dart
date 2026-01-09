import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show showUpdateUrlsDialog;
import 'package:tts_mod_vault/src/mods/components/custom_tooltip.dart';
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkBackupBehaviorEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart'
    show Mod, ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        bulkActionsProvider,
        multiModsProvider,
        selectedModTypeProvider;

class MultiSelectView extends HookConsumerWidget {
  const MultiSelectView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMods = ref.watch(multiModsProvider);
    final modType = ref.watch(selectedModTypeProvider);
    final actionInProgress = ref.watch(actionInProgressProvider);

    // Check if all selected mods are of type 'mod' for Update Mods button
    final allModsAreMod =
        selectedMods.every((mod) => mod.modType == ModTypeEnum.mod);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          alignment: Alignment.topLeft,
          padding: EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${selectedMods.length} ${modType.label}s selected',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              CustomTooltip(
                message: 'Clear all',
                child: IconButton(
                  icon: const Icon(Icons.clear),
                  padding: EdgeInsets.zero,
                  style: ButtonStyle(
                    backgroundColor:
                        WidgetStateProperty.all(Colors.white), // Background
                    foregroundColor:
                        WidgetStateProperty.all(Colors.black), // Icon
                  ),
                  constraints: BoxConstraints(maxHeight: 26, maxWidth: 26),
                  onPressed: actionInProgress
                      ? null
                      : () {
                          ref.read(multiModsProvider.notifier).state = {};
                          //ref.read(selectedModProvider.notifier).state = null;
                        },
                ),
              ),
            ],
          ),
        ),

        // Scrollable list of selected mod names
        Expanded(
          child: ListView.builder(
            itemCount: selectedMods.length,
            itemBuilder: (context, index) {
              final mod = selectedMods.elementAt(index);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  mod.saveName,
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download'),
                onPressed: actionInProgress
                    ? null
                    : () => _downloadAll(ref, selectedMods.toList()),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.archive, size: 18),
                label: const Text('Backup'),
                onPressed: actionInProgress
                    ? null
                    : () => _backupAll(ref, selectedMods.toList()),
              ),
              ElevatedButton.icon(
                icon: Row(
                  children: [
                    const Icon(Icons.download),
                    const Icon(Icons.archive),
                  ],
                ),
                label: const Text('Download & Backup'),
                onPressed: actionInProgress
                    ? null
                    : () => _downloadAndBackup(ref, selectedMods.toList()),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Update URLs'),
                onPressed: actionInProgress
                    ? null
                    : () => _updateUrls(context, ref, selectedMods.toList()),
              ),
              if (allModsAreMod)
                ElevatedButton.icon(
                  icon: const Icon(Icons.update),
                  label: const Text('Update mods'),
                  onPressed: actionInProgress
                      ? null
                      : () => _updateMods(ref, selectedMods.toList()),
                ),
            ],
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
    ref.read(bulkActionsProvider.notifier).downloadAndBackupAllMods(
        selectedMods, BulkBackupBehaviorEnum.replace, null);
  }

  void _updateUrls(
      BuildContext context, WidgetRef ref, List<Mod> selectedMods) {
    showUpdateUrlsDialog(
      context,
      ref,
      onConfirm: (oldUrlPrefix, newUrlPrefix, renameFile) {
        ref.read(bulkActionsProvider.notifier).updateUrlPrefixesAllMods(
              selectedMods,
              oldUrlPrefix.split('|'),
              newUrlPrefix,
              renameFile,
            );
      },
    );
  }

  void _updateMods(WidgetRef ref, List<Mod> selectedMods) {
    // updateModsAll requires forceUpdate parameter
    ref.read(bulkActionsProvider.notifier).updateModsAll(selectedMods, false);
  }
}
