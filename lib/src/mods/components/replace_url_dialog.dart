import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useFocusNode, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;

void showReplaceUrlDialog(
  BuildContext context,
  WidgetRef ref,
  Asset asset,
  Mod mod,
) {
  if (context.mounted) {
    showDialog(
      context: context,
      builder: (context) {
        return ReplaceUrlDialog(asset: asset, mod: mod);
      },
    );
  }
}

class ReplaceUrlDialog extends HookConsumerWidget {
  final Asset asset;
  final Mod mod;

  const ReplaceUrlDialog({super.key, required this.asset, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textFieldController = useTextEditingController();
    final textFieldFocusNode = useFocusNode();
    final renameFileBox = useState(asset.fileExists);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        title: Text('Replace URL'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 950,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current URL:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.white,
                  ),
                  child: SelectableText(
                    asset.url,
                    style: TextStyle(fontSize: 16, color: Colors.black),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'New URL:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: textFieldController,
                  focusNode: textFieldFocusNode,
                  cursorColor: Colors.black,
                  style: TextStyle(
                      fontSize: 16, color: Colors.black, letterSpacing: 0.26),
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    hintText: 'Enter new URL',
                  ),
                ),
                if (asset.fileExists) ...[
                  SizedBox(height: 16),
                  Row(
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
                        'Rename existing file',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Validate URL input
              if (textFieldController.text.trim().isEmpty) {
                // You might want to show a snackbar or error message here
                return;
              }

              // Handle the URL replacement logic here
              // You can access:
              // - textFieldController.text for the new URL
              // - renameFileBox.value for rename checkbox state
              // - asset for the original asset data

              Navigator.pop(context);
            },
            child: Text('Apply'),
          ),
        ],
      ),
    );
  }
}
