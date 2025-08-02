import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show BulkBackupBehaviorEnum;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;

class BulkBackupDialog extends HookConsumerWidget {
  final String title;
  final BulkBackupBehaviorEnum initialBehavior;
  final Function(BulkBackupBehaviorEnum behavior, String folder) onConfirm;

  const BulkBackupDialog({
    super.key,
    required this.title,
    required this.initialBehavior,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupsDir = ref.watch(directoriesProvider).backupsDir;
    final selectedBehavior = useState(initialBehavior);
    final selectedFolder = useState(ref.read(directoriesProvider).backupsDir);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        actions: [
          Row(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: () async {
                  String? folder = await FilePicker.platform.getDirectoryPath(
                    lockParentWindow: true,
                    initialDirectory: backupsDir.isEmpty ? null : backupsDir,
                  );
                  if (folder != null) {
                    selectedFolder.value = folder;
                  }
                },
                child: const Text('Select'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedFolder.value.isEmpty
                    ? null
                    : () {
                        onConfirm.call(
                          selectedBehavior.value,
                          selectedFolder.value,
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
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            Row(
              spacing: 8,
              children: [
                const Expanded(
                  child: Text('Existing backup behavior:'),
                ),
                DropdownButton<BulkBackupBehaviorEnum>(
                  value: selectedBehavior.value,
                  dropdownColor: Colors.white,
                  style: TextStyle(color: Colors.white),
                  underline: Container(
                    height: 2,
                    color: Colors.white,
                  ),
                  focusColor: Colors.transparent,
                  selectedItemBuilder: (BuildContext context) {
                    return BulkBackupBehaviorEnum.values.map<Widget>((item) {
                      return Container(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.label,
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList();
                  },
                  items: BulkBackupBehaviorEnum.values.map((behavior) {
                    return DropdownMenuItem<BulkBackupBehaviorEnum>(
                      value: behavior,
                      child: Text(
                        behavior.label,
                        style: const TextStyle(color: Colors.black),
                      ),
                    );
                  }).toList(),
                  onChanged: (BulkBackupBehaviorEnum? newValue) {
                    if (newValue != null) {
                      selectedBehavior.value = newValue;
                    }
                  },
                ),
              ],
            ),
            Text('Save folder: ${selectedFolder.value}'),
          ],
        ),
      ),
    );
  }
}
