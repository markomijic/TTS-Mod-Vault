import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useMemoized, useEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/provider.dart'
    show existingBackupsProvider, loaderProvider;

class RenameOldBackupsDialog extends HookConsumerWidget {
  const RenameOldBackupsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final existingBackups = ref.watch(existingBackupsProvider);

    final selectedIndices = useState<Set<int>>({});
    final renamingInProgress = useState(false);

    // Calculate which files need fixing and what they should be renamed to
    final renamingData = useMemoized(() {
      final data = <RenameData>[];

      for (int i = 0; i < existingBackups.backups.length; i++) {
        final original = existingBackups.backups[i].filename;
        final fixed = fixFilename(original);

        if (original != fixed) {
          data.add(RenameData(
            index: i,
            original: original,
            originalFilePath: existingBackups.backups[i].filepath,
            fixed: fixed,
          ));
        }
      }

      return data;
    }, [existingBackups.backups]);

    // Initialize selected items when data loads
    useEffect(() {
      if (renamingData.isNotEmpty && selectedIndices.value.isEmpty) {
        selectedIndices.value = Set.from(renamingData.map((d) => d.index));
      }
      return null;
    }, [renamingData]);

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              CustomTooltip(
                message:
                    'TTS Mod Vault versions 1.0.0 - 1.1.0 used a backup name format that did not fully match the one used by TTS Mod Backup.\n\n'
                    'In version 1.2.0 the Backup State feature has been added. It has been made to work with backups created by TTS Mod Backup and therefore backups by TTS Mod Vault must match the naming format.\n'
                    'This tool can rename backups made with TTS Mod Vault 1.0.0 - 1.1.0 to use the new backup name format and therefore work with the new Backup State feature.\n\n'
                    'If you find any issue where the new format does not match what TTS Mod Backup would have created, please let me know.\n'
                    'Apologies for any inconvenience this may have caused, and thank you for your understanding.\n\n\n'
                    'New naming format examples:\n1234.json => modSaveName (1234).ttsmod\nfileName.json => modSaveName.ttsmod',
                child: Icon(
                  Icons.help_outline,
                  size: 30,
                ),
              ),
              Text(
                  'Rename backups created by TTS Mod Vault versions 1.0.0 - 1.1.0 to match backup naming format in 1.2.0 to work with Backup State feature'),
            ],
          ),
          Expanded(
            child: Column(
              spacing: 8,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Current Name',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Fixed Name',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Expanded(
                  child: renamingData.isEmpty
                      ? Center(
                          child: Text(
                            'All files are correctly named!',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        )
                      : ListView.builder(
                          itemCount: renamingData.length,
                          itemBuilder: (context, index) {
                            final data = renamingData[index];
                            final isSelected =
                                selectedIndices.value.contains(data.index);

                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[850],
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                spacing: 4,
                                children: [
                                  SizedBox.shrink(),
                                  Expanded(
                                    child: CustomTooltip(
                                      waitDuration: Duration(milliseconds: 350),
                                      message: data.fixed,
                                      child: Text(
                                        data.original,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: CustomTooltip(
                                      waitDuration: Duration(milliseconds: 350),
                                      message: data.fixed,
                                      child: Text(
                                        data.fixed,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Checkbox(
                                      value: isSelected,
                                      checkColor: Colors.black,
                                      activeColor: Colors.white,
                                      onChanged: (value) {
                                        final newSet = Set<int>.from(
                                            selectedIndices.value);
                                        if (value == true) {
                                          newSet.add(data.index);
                                        } else {
                                          newSet.remove(data.index);
                                        }
                                        selectedIndices.value = newSet;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: () {
                  selectedIndices.value =
                      Set.from(renamingData.map((d) => d.index));
                },
                child: const Text('Select All'),
              ),
              ElevatedButton(
                onPressed: () {
                  selectedIndices.value = {};
                },
                child: const Text('Deselect All'),
              ),
              Text(
                '${selectedIndices.value.length} of ${renamingData.length} selected',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              CustomTooltip(
                message: 'Data will be refreshed after renaming files',
                child: ElevatedButton.icon(
                  onPressed: selectedIndices.value.isEmpty
                      ? null
                      : () async {
                          if (renamingInProgress.value) return;

                          renamingInProgress.value = true;

                          final List<RenameData> filesToRename = [];

                          for (final data in renamingData) {
                            if (selectedIndices.value.contains(data.index)) {
                              filesToRename.add(data);
                            }
                          }

                          bool filesRenamed = false;

                          for (final file in filesToRename) {
                            try {
                              if (file.originalFilePath.isNotEmpty) {
                                await File(file.originalFilePath).rename(p
                                    .joinAll([
                                  p.dirname(file.originalFilePath),
                                  file.fixed
                                ]));

                                filesRenamed = true;
                              }
                            } catch (e) {
                              debugPrint('Renaming error: $e');
                            }
                          }

                          if (filesRenamed) {
                            ref.read(loaderProvider).refreshAppData();
                          }

                          if (context.mounted) {
                            Navigator.pop(context, filesToRename);
                          }
                        },
                  icon: const Icon(Icons.edit),
                  label: Text(
                    selectedIndices.value.isEmpty
                        ? 'Select files to rename'
                        : 'Rename ${selectedIndices.value.length} file${selectedIndices.value.length == 1 ? '' : 's'}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String fixFilename(String filename) {
    // Only process .ttsmod files
    if (!filename.endsWith('.ttsmod')) {
      return filename;
    }

    // Match pattern: anything(something).ttsmod
    final regExp = RegExp(r'^(.*)\(([^)]+)\)\.ttsmod$');
    final match = regExp.firstMatch(filename);

    if (match == null) {
      return filename; // No parentheses found, return as is
    }

    final baseName = match.group(1)!.trim();
    final insideParens = match.group(2)!;

    // Number inside parentheses - add space
    if (int.tryParse(insideParens) != null) {
      return '$baseName ($insideParens).ttsmod';
    }

    return '$baseName.ttsmod';
  }
}

class RenameData {
  final int index;
  final String original;
  final String fixed;
  final String originalFilePath;

  const RenameData({
    required this.index,
    required this.original,
    required this.fixed,
    required this.originalFilePath,
  });
}
