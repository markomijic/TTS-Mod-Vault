import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart' show modsProvider;
import 'package:tts_mod_vault/src/utils.dart'
    show updateUrlsHelp, updateUrlsInstruction;

void showUpdateUrlsDialog(
  BuildContext context,
  WidgetRef ref,
  Mod mod,
) {
  if (context.mounted) {
    showDialog(
      context: context,
      builder: (context) {
        return UpdateUrlsDialog(
          mod: mod,
        );
      },
    );
  }
}

class UpdateUrlsDialog extends HookConsumerWidget {
  final Mod mod;

  const UpdateUrlsDialog({
    super.key,
    required this.mod,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oldPrefixTextFieldController = useTextEditingController();
    final newPrefixTextFieldController = useTextEditingController();

    final renameFileBox = useState(true);
    final replacingUrl = useState(false);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Stack(
        children: [
          AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Update URLs'),
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
              ElevatedButton(
                onPressed: () async {
                  final oldUrlPrefix = oldPrefixTextFieldController.text.trim();
                  final newUrlPrefix = newPrefixTextFieldController.text.trim();

                  if (newUrlPrefix.isEmpty || oldUrlPrefix.isEmpty) return;

                  try {
                    replacingUrl.value = true;

                    await ref.read(modsProvider.notifier).updateUrlPrefixes(
                          mod,
                          oldUrlPrefix.split('|'),
                          newUrlPrefix,
                          renameFileBox.value,
                        );

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    debugPrint('Replacing URL error: $e');
                  } finally {
                    replacingUrl.value = false;
                  }
                },
                child: Text('Apply'),
              ),
            ],
          ),
          if (replacingUrl.value)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
