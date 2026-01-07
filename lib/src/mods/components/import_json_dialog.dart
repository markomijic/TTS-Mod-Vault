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
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

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

    final jsonFile = useState<FilePickerResult?>(null);
    final folderPath = useState(workshopDir);
    final modType = useState(ModTypeEnum.mod);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        contentPadding: EdgeInsets.all(16),
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
                onPressed: jsonFile.value == null || folderPath.value.isEmpty
                    ? null
                    : () {
                        final filePath = jsonFile.value!.files.single.path!;
                        onConfirm.call(
                          filePath,
                          folderPath.value,
                          modType.value,
                        );
                        Navigator.pop(context);
                      },
                child: const Text('Import'),
              ),
            ],
          ),
        ],
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              const Text(
                'Import JSON',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  Text(
                    'File: ${jsonFile.value != null ? jsonFile.value!.files.single.name : ''}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  Spacer(),
                ],
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
                      jsonFile.value = result;
                    }
                  } catch (e) {
                    if (context.mounted) showSnackBar(context, e.toString());
                  }
                },
                icon: const Icon(Icons.file_open),
                label: const Text('Select JSON'),
              ),
              // const Divider(),
              Row(
                spacing: 8,
                children: [
                  Text(
                    'Type:',
                    style: TextStyle(fontSize: 16),
                  ),
                  DropdownButton<ModTypeEnum>(
                    value: modType.value,
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
                          type.label.toUpperCase(),
                          style: const TextStyle(color: Colors.black),
                        ),
                      );
                    }).toList(),
                    onChanged: (ModTypeEnum? newValue) {
                      if (newValue != null) {
                        modType.value = newValue;

                        switch (newValue) {
                          case ModTypeEnum.mod:
                            folderPath.value = workshopDir;
                            break;
                          case ModTypeEnum.save:
                            folderPath.value = savesDir;
                            break;
                          case ModTypeEnum.savedObject:
                            folderPath.value = savedObjectsDir;
                            break;
                        }
                      }
                    },
                  ),
                ],
              ),
              Text(
                'Import to: ${folderPath.value}',
                style: const TextStyle(fontSize: 16),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final initialFolder = folderPath.value;
                    final normalizedPath = path.normalize(initialFolder);
                    final folder = await FilePicker.platform.getDirectoryPath(
                      lockParentWindow: true,
                      initialDirectory: normalizedPath,
                    );
                    if (folder != null) {
                      folderPath.value = folder;
                    }
                  } catch (e) {
                    if (context.mounted) showSnackBar(context, e.toString());
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Select folder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
