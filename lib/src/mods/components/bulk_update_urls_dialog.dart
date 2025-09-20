import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/utils.dart'
    show updateUrlsHelp, updateUrlsInstruction;

void showBulkUpdateUrlsDialog(
  BuildContext context,
  WidgetRef ref,
  Function(String oldUrlPrefix, String newUrlPrefix, bool renameFile) onConfirm,
) {
  if (context.mounted) {
    showDialog(
      context: context,
      builder: (context) {
        return BulkUpdateUrlsDialog(onConfirm: onConfirm);
      },
    );
  }
}

class BulkUpdateUrlsDialog extends HookConsumerWidget {
  final Function(String oldUrlPrefix, String newUrlPrefix, bool renameFile)
      onConfirm;

  const BulkUpdateUrlsDialog({super.key, required this.onConfirm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oldPrefixTextFieldController = useTextEditingController();
    final newPrefixTextFieldController = useTextEditingController();

    final renameFileBox = useState(true);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Stack(
        children: [
          AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bulk Update URLs'),
                CustomTooltip(
                  message: updateUrlsHelp,
                  child: Icon(
                    Icons.info_outline,
                    size: 30,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 950,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      updateUrlsInstruction,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  SizedBox(height: 32),
                  Text(
                    'Old URL prefix:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    controller: oldPrefixTextFieldController,
                    cursorColor: Colors.black,
                    style: TextStyle(fontSize: 16, color: Colors.black),
                    scrollPadding: EdgeInsets.all(0),
                    decoration: InputDecoration(
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                      hintText: 'Enter new URL',
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'New URL prefix:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    controller: newPrefixTextFieldController,
                    cursorColor: Colors.black,
                    style: TextStyle(fontSize: 16, color: Colors.black),
                    scrollPadding: EdgeInsets.all(0),
                    decoration: InputDecoration(
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                      hintText: 'Enter new URL',
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Checkbox(
                        value: renameFileBox.value,
                        checkColor: Colors.black,
                        activeColor: Colors.white,
                        onChanged: (value) {
                          renameFileBox.value = value ?? false;
                        },
                      ),
                      Text(
                        'Rename existing files',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              CustomTooltip(
                message: 'Data will be refreshed after the bulk action ends',
                child: ElevatedButton(
                  onPressed: () async {
                    final oldUrlPrefix =
                        oldPrefixTextFieldController.text.trim();
                    final newUrlPrefix =
                        newPrefixTextFieldController.text.trim();

                    if (newUrlPrefix.isEmpty || oldUrlPrefix.isEmpty) return;

                    onConfirm.call(
                      oldUrlPrefix,
                      newUrlPrefix,
                      renameFileBox.value,
                    );
                    Navigator.pop(context);
                  },
                  child: Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
