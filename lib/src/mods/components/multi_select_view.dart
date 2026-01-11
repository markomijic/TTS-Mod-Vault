import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show showUpdateUrlsDialog, BulkBackupDialog, CustomTooltip;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkBackupBehaviorEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart'
    show
        actionInProgressProvider,
        bulkActionsProvider,
        multiModsProvider,
        selectedModTypeProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show showConfirmDialogWithCheckbox;

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
        // Header with count
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
          child: Text(
            '${selectedMods.length} ${modType.label}s selected',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
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
                onPressed: () {
                  if (actionInProgress) return;

                  ref
                      .read(bulkActionsProvider.notifier)
                      .downloadAllMods(selectedMods.toList());
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.archive, size: 18),
                label: const Text('Backup'),
                onPressed: () {
                  if (actionInProgress) return;

                  showDialog(
                    context: context,
                    builder: (context) => BulkBackupDialog(
                      title: 'Backup all',
                      initialBehavior:
                          BulkBackupBehaviorEnum.replaceIfOutOfDate,
                      onConfirm: (behavior, folder) {
                        ref.read(bulkActionsProvider.notifier).backupAllMods(
                              selectedMods.toList(),
                              behavior,
                              folder,
                            );
                      },
                    ),
                  );
                },
              ),
              ElevatedButton.icon(
                icon: Row(
                  children: [
                    const Icon(Icons.download),
                    const Icon(Icons.archive),
                  ],
                ),
                label: const Text('Download & Backup'),
                onPressed: () {
                  if (actionInProgress) return;

                  showDialog(
                    context: context,
                    builder: (context) => BulkBackupDialog(
                      title: 'Download & backup all',
                      initialBehavior:
                          BulkBackupBehaviorEnum.replaceIfOutOfDate,
                      onConfirm: (behavior, folder) {
                        ref
                            .read(bulkActionsProvider.notifier)
                            .downloadAndBackupAllMods(
                              selectedMods.toList(),
                              behavior,
                              folder,
                            );
                      },
                    ),
                  );
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Update URLs'),
                onPressed: () {
                  if (actionInProgress) return;

                  showUpdateUrlsDialog(
                    context,
                    ref,
                    onConfirm: (oldUrlPrefix, newUrlPrefix, renameFile) {
                      ref
                          .read(bulkActionsProvider.notifier)
                          .updateUrlPrefixesAllMods(
                            selectedMods.toList(),
                            oldUrlPrefix.split('|'),
                            newUrlPrefix,
                            renameFile,
                          );
                    },
                  );
                },
              ),
              if (allModsAreMod)
                ElevatedButton.icon(
                  icon: const Icon(Icons.update),
                  label: const Text('Update mods'),
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
                      onConfirm: (forceUpdate) {
                        ref.read(bulkActionsProvider.notifier).updateModsAll(
                              selectedMods.toList(),
                              forceUpdate,
                              context,
                            );
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
