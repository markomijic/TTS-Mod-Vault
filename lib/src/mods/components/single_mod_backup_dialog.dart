import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/backup/backup_status_enum.dart'
    show ExistingBackupStatusEnum;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show PostBackupDeletionEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show directoriesProvider, settingsProvider;

enum BackupLocationChoice { replace, selectNew }

class SingleModBackupDialog extends HookConsumerWidget {
  final Mod mod;
  final Function(
    String? backupFolder,
    bool downloadMissingFirst,
    PostBackupDeletionEnum postBackupDeletion,
  ) onConfirm;

  const SingleModBackupDialog({
    super.key,
    required this.mod,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupsDir = ref.watch(directoriesProvider).backupsDir;
    final showBackupState = ref.watch(settingsProvider).showBackupState;

    final hasExistingBackup =
        mod.backupStatus != ExistingBackupStatusEnum.noBackup;
    final existingBackupFolder = hasExistingBackup && mod.backup != null
        ? p.dirname(mod.backup!.filepath)
        : null;

    final hasMissingAssets = useMemoized(() {
      return mod.getAllAssets().any((asset) => !asset.fileExists);
    }, [mod]);

    final locationChoice = useState(BackupLocationChoice.replace);
    final selectedFolder = useState(backupsDir);
    final downloadMissingFirst = useState(false);
    final selectedPostBackupDeletion = useState(PostBackupDeletionEnum.none);

    // Determine which folder will be used for backup
    final effectiveFolder = hasExistingBackup &&
            locationChoice.value == BackupLocationChoice.replace
        ? existingBackupFolder
        : selectedFolder.value;

    final showWarning = showBackupState && backupsDir.isEmpty;
    final setBackupFolderMessage =
        "Set a backup folder in Settings to show backup state after a restart or data refresh\nOr disable Backup State feature in Settings to hide this warning";

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        actions: [
          Row(
            spacing: 8,
            children: [
              if (!hasExistingBackup ||
                  locationChoice.value == BackupLocationChoice.selectNew)
                ElevatedButton.icon(
                  onPressed: () async {
                    String? folder = await FilePicker.platform.getDirectoryPath(
                      lockParentWindow: true,
                      initialDirectory: backupsDir.isEmpty ? null : backupsDir,
                    );
                    if (folder != null) {
                      selectedFolder.value = folder;
                    }
                  },
                  icon: Icon(Icons.folder),
                  label: const Text('Select folder'),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: effectiveFolder == null || effectiveFolder.isEmpty
                    ? null
                    : () {
                        onConfirm.call(
                          effectiveFolder,
                          downloadMissingFirst.value,
                          selectedPostBackupDeletion.value,
                        );
                        Navigator.pop(context);
                      },
                child: const Text('Confirm'),
              ),
            ],
          ),
        ],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            Text(
              'Backup "${mod.saveName}"',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            // Backup location choice (only if backup exists)
            if (hasExistingBackup)
              Row(
                spacing: 8,
                children: [
                  const Expanded(
                    child: Text('Backup location:'),
                  ),
                  DropdownButton<BackupLocationChoice>(
                    value: locationChoice.value,
                    dropdownColor: Colors.white,
                    style: TextStyle(color: Colors.white),
                    underline: Container(
                      height: 2,
                      color: Colors.white,
                    ),
                    focusColor: Colors.transparent,
                    selectedItemBuilder: (BuildContext context) {
                      return [
                        Container(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Replace existing',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        Container(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Select new folder',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ];
                    },
                    items: [
                      DropdownMenuItem<BackupLocationChoice>(
                        value: BackupLocationChoice.replace,
                        child: Text(
                          'Replace existing',
                          style: const TextStyle(color: Colors.black),
                        ),
                      ),
                      DropdownMenuItem<BackupLocationChoice>(
                        value: BackupLocationChoice.selectNew,
                        child: Text(
                          'Select new folder',
                          style: const TextStyle(color: Colors.black),
                        ),
                      ),
                    ],
                    onChanged: (BackupLocationChoice? newValue) {
                      if (newValue != null) {
                        locationChoice.value = newValue;
                      }
                    },
                  ),
                ],
              ),
            // Download missing assets checkbox
            Row(
              spacing: 8,
              children: [
                Checkbox(
                  value: downloadMissingFirst.value,
                  onChanged: hasMissingAssets
                      ? (value) {
                          downloadMissingFirst.value = value ?? false;
                        }
                      : null,
                  checkColor: Colors.black,
                  activeColor: Colors.white,
                ),
                Expanded(
                  child: Text(
                    hasMissingAssets
                        ? 'Download missing assets first'
                        : 'No missing assets',
                    style: TextStyle(
                      color: hasMissingAssets ? Colors.white : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            // After backup dropdown
            Row(
              spacing: 8,
              children: [
                const Expanded(
                  child: Text('After backup:'),
                ),
                DropdownButton<PostBackupDeletionEnum>(
                  value: selectedPostBackupDeletion.value,
                  dropdownColor: Colors.white,
                  style: TextStyle(color: Colors.white),
                  underline: Container(
                    height: 2,
                    color: Colors.white,
                  ),
                  focusColor: Colors.transparent,
                  selectedItemBuilder: (BuildContext context) {
                    return PostBackupDeletionEnum.values.map<Widget>((item) {
                      return Container(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.label,
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList();
                  },
                  items: PostBackupDeletionEnum.values.map((deletion) {
                    return DropdownMenuItem<PostBackupDeletionEnum>(
                      value: deletion,
                      child: Text(
                        deletion.label,
                        style: const TextStyle(color: Colors.black),
                      ),
                    );
                  }).toList(),
                  onChanged: (PostBackupDeletionEnum? newValue) {
                    if (newValue != null) {
                      selectedPostBackupDeletion.value = newValue;
                    }
                  },
                ),
              ],
            ),
            // Warning about backup folder
            if (showWarning)
              Row(
                spacing: 8,
                children: [
                  Icon(Icons.warning_amber_rounded),
                  Expanded(child: Text(setBackupFolderMessage)),
                ],
              ),
            // Show current backup path
            if (hasExistingBackup &&
                locationChoice.value == BackupLocationChoice.replace)
              Text('Backup to: $existingBackupFolder')
            else
              Text(
                  'Backup to: ${selectedFolder.value.isEmpty ? "(select folder)" : selectedFolder.value}'),
          ],
        ),
      ),
    );
  }
}
