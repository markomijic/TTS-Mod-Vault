import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart'
    show FilePicker, FilePickerResult, FileType;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;

class ImportJsonDialog extends HookConsumerWidget {
  final Function(
    String jsonFilePath,
    String destinationFolder,
    ModTypeEnum modType,
  ) onConfirm;

  const ImportJsonDialog({
    super.key,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workshopDir = ref.watch(directoriesProvider).workshopDir;
    final savesDir = ref.watch(directoriesProvider).savesDir;
    final savedObjectsDir = ref.watch(directoriesProvider).savedObjectsDir;

    final selectedJsonFile = useState<FilePickerResult?>(null);
    final selectedDestination = useState(workshopDir);
    final selectedModType = useState(ModTypeEnum.mod);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        actions: [
          Row(
            spacing: 8,
            children: [
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedJsonFile.value == null ||
                        selectedDestination.value.isEmpty
                    ? null
                    : () {
                        final filePath =
                            selectedJsonFile.value!.files.single.path!;
                        onConfirm.call(
                          filePath,
                          selectedDestination.value,
                          selectedModType.value,
                        );
                        Navigator.pop(context);
                      },
                child: const Text('Import'),
              ),
            ],
          ),
        ],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            const Text(
              'Import JSON',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            Row(
              spacing: 8,
              children: [
                const Expanded(
                  child: Text('JSON file:'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        lockParentWindow: true,
                        allowedExtensions: ['json'],
                        allowMultiple: false,
                      );
                      if (result != null && result.files.isNotEmpty) {
                        selectedJsonFile.value = result;
                      }
                    } catch (e) {
                      // Handle error silently
                    }
                  },
                  icon: const Icon(Icons.file_open),
                  label: const Text('Select JSON'),
                ),
              ],
            ),
            if (selectedJsonFile.value != null)
              Text(
                'Selected: ${selectedJsonFile.value!.files.single.name}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const Divider(),
            Row(
              spacing: 8,
              children: [
                const Expanded(
                  child: Text('Mod type:'),
                ),
                DropdownButton<ModTypeEnum>(
                  value: selectedModType.value,
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: Colors.white),
                  underline: Container(
                    height: 2,
                    color: Colors.white,
                  ),
                  focusColor: Colors.transparent,
                  selectedItemBuilder: (BuildContext context) {
                    return ModTypeEnum.values.map<Widget>((item) {
                      return Container(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.label.toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList();
                  },
                  items: ModTypeEnum.values.map((type) {
                    return DropdownMenuItem<ModTypeEnum>(
                      value: type,
                      child: Text(
                        type.label,
                        style: const TextStyle(color: Colors.black),
                      ),
                    );
                  }).toList(),
                  onChanged: (ModTypeEnum? newValue) {
                    if (newValue != null) {
                      selectedModType.value = newValue;
                      // Update destination based on type
                      switch (newValue) {
                        case ModTypeEnum.mod:
                          selectedDestination.value =
                              path.normalize(workshopDir);
                          break;
                        case ModTypeEnum.save:
                          selectedDestination.value = path.normalize(savesDir);
                          break;
                        case ModTypeEnum.savedObject:
                          selectedDestination.value =
                              path.normalize(savedObjectsDir);
                          break;
                      }
                    }
                  },
                ),
              ],
            ),
            Row(
              spacing: 8,
              children: [
                const Expanded(
                  child: Text('Destination folder:'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    String? folder = await FilePicker.platform.getDirectoryPath(
                      lockParentWindow: true,
                      dialogTitle: 'Select destination folder',
                      initialDirectory: selectedDestination.value.isEmpty
                          ? null
                          : selectedDestination.value,
                    );
                    if (folder != null) {
                      selectedDestination.value = folder;
                    }
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Select'),
                ),
              ],
            ),
            Text(
              'Import to: ${selectedDestination.value}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
