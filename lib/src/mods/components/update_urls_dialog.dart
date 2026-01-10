import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/provider.dart'
    show selectedModTypeProvider, settingsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show copyToClipboard, updateUrlsHelp, updateUrlsInstruction;

void showUpdateUrlsDialog(
  BuildContext context,
  WidgetRef ref, {
  required Function(
    String oldUrlPrefix,
    String newUrlPrefix,
    bool renameFile,
  ) onConfirm,
}) {
  if (context.mounted) {
    showDialog(
      context: context,
      builder: (context) {
        return UpdateUrlsDialog(onConfirm: onConfirm);
      },
    );
  }
}

class UpdateUrlsDialog extends HookConsumerWidget {
  final Function(
    String oldUrlPrefix,
    String newUrlPrefix,
    bool renameFile,
  ) onConfirm;

  const UpdateUrlsDialog({
    super.key,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(settingsProvider).urlReplacementPresets;

    final oldPrefixTextFieldController = useTextEditingController();
    final newPrefixTextFieldController = useTextEditingController();

    final showExample = useState(false);
    final renameFileBox = useState(true);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Stack(
        children: [
          AlertDialog(
            contentPadding: EdgeInsets.symmetric(horizontal: 24),
            title: Row(
              children: [
                Text('Update URLs'),
                Spacer(),
                CustomTooltip(
                  message: showExample.value ? 'Hide example' : 'Show example',
                  child: IconButton(
                    icon: Icon(
                      showExample.value ? Icons.help : Icons.help_outline,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      showExample.value = !showExample.value;
                    },
                  ),
                ),
                CustomTooltip(
                  message: 'Copy | pipe symbol to clipboard',
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => copyToClipboard(
                      context,
                      '|',
                      showSnackBarAfterCopying: false,
                    ),
                    icon: Icon(Icons.copy),
                  ),
                ),
                CustomTooltip(
                  message: updateUrlsHelp,
                  child: Icon(
                    Icons.info_outline,
                    size: 30,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showExample.value)
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
                if (presets.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((preset) {
                      return OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.white),
                        ),
                        onPressed: () {
                          oldPrefixTextFieldController.text = preset.oldUrl;
                          newPrefixTextFieldController.text = preset.newUrl;
                        },
                        child: Text(preset.label),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 16),
                ],
                Text(
                  'Old prefix',
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
                  'New prefix',
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
                      'Rename existing asset files',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                SizedBox(height: 8),
              ],
            ),
            actionsAlignment: MainAxisAlignment.start,
            actions: [
              Icon(Icons.warning_amber_rounded, size: 32),
              Text(
                'This action will edit your ${ref.read(selectedModTypeProvider).label} JSON files',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(width: 300),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final oldUrlPrefix = oldPrefixTextFieldController.text.trim();
                  final newUrlPrefix = newPrefixTextFieldController.text.trim();

                  if (newUrlPrefix.isEmpty || oldUrlPrefix.isEmpty) return;

                  onConfirm(oldUrlPrefix, newUrlPrefix, renameFileBox.value);
                  Navigator.pop(context);
                },
                icon: Icon(Icons.edit),
                label: Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
