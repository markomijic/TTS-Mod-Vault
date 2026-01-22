import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/asset/models/asset_model.dart'
    show Asset;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart'
    show AssetTypeEnum;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show modsProvider, selectedModTypeProvider;

void showReplaceUrlDialog(
  BuildContext context,
  WidgetRef ref,
  Asset asset,
  AssetTypeEnum assetType,
  Mod mod,
) {
  if (context.mounted) {
    showDialog(
      context: context,
      builder: (context) {
        return ReplaceUrlDialog(
          asset: asset,
          assetType: assetType,
          mod: mod,
        );
      },
    );
  }
}

class ReplaceUrlDialog extends HookConsumerWidget {
  final Asset asset;
  final AssetTypeEnum assetType;
  final Mod mod;

  const ReplaceUrlDialog({
    super.key,
    required this.asset,
    required this.assetType,
    required this.mod,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textFieldController = useTextEditingController();
    final renameFileBox = useState(asset.fileExists);
    final replacingUrl = useState(false);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Stack(
        children: [
          AlertDialog(
            title: Text('Replace URL'),
            content: SizedBox(
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
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'New URL:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    controller: textFieldController,
                    cursorColor: Colors.black,
                    style: TextStyle(fontSize: 16, color: Colors.black),
                    scrollPadding: EdgeInsets.all(0),
                    decoration: InputDecoration(
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                      hintText: 'Enter new URL',
                    ),
                  ),
                  if (asset.fileExists) ...[
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Checkbox(
                          value: renameFileBox.value,
                          checkColor: Colors.black,
                          activeColor: Colors.white,
                          visualDensity: VisualDensity.compact,
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
            actionsAlignment: MainAxisAlignment.start,
            actions: [
              Icon(Icons.warning_amber_rounded, size: 32),
              Text(
                'This action will edit your ${ref.read(selectedModTypeProvider).label} JSON file',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(width: 406),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final newUrl = textFieldController.text.trim();
                  if (newUrl.isEmpty) return;

                  try {
                    replacingUrl.value = true;

                    await ref.read(modsProvider.notifier).updateModAsset(
                          selectedMod: mod,
                          oldAsset: asset,
                          assetType: assetType,
                          newAssetUrl: newUrl,
                          renameFile: renameFileBox.value,
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
                icon: Icon(Icons.edit),
                label: Text('Apply'),
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
