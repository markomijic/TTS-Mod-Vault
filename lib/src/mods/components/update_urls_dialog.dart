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

const String updateUrlsHelp = '''
The Update URLs feature works by replacing the beginning of a URL

Example (single old prefix):
• Old prefix: http://pastebin.com/raw.php?i=
• New prefix: https://pastebin.com/raw/

If your mod contains: http://pastebin.com/raw.php?i=1234, http://pastebin.com/raw.php?i=example
They will be updated to: https://pastebin.com/raw/1234, https://pastebin.com/raw/example

Example (multiple old prefixes):
• Old prefixes: http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/
• New prefix: https://pastebin.com/raw/

If your mod contains: http://pastebin.com/raw.php?i=abcd, http://pastebin.com/raw/5678, http://pastebin.com/example2
They will be updated to: https://pastebin.com/raw/abcd, https://pastebin.com/raw/5678, https://pastebin.com/raw/example2
''';

const String updateUrlsInstruction =
    'You can enter multiple old prefixes by separating them with the | symbol\nFor example: http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/\n\nThere must be exactly one new prefix, for example: https://pastebin.com/raw/';

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
                  //message: updateUrlsHelp,
                  richMessage: TextSpan(
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      height: 1.6,
                    ),
                    children: [
                      TextSpan(
                        text: updateUrlsHelp,
                      ),
                    ],
                  ),
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
              ElevatedButton(
                onPressed: () async {
                  final newUrlPrefix = newPrefixTextFieldController.text.trim();
                  final oldUrlPrefix = oldPrefixTextFieldController.text.trim();
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
