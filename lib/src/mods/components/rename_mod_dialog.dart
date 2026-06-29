import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart' show modsProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class RenameModDialog extends HookConsumerWidget {
  final Mod mod;

  const RenameModDialog({super.key, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController(text: mod.saveName);
    final isRenaming = useState(false);
    final hasBackup = mod.backup != null;
    final renameBackup = useState(true);

    Future<void> rename() async {
      final name = nameController.text.trim();
      if (name.isEmpty) {
        showSnackBar(context, 'Please enter a valid name');
        return;
      }

      isRenaming.value = true;

      final renamed = await ref.read(modsProvider.notifier).renameMod(
            mod,
            name,
            renameBackup: hasBackup && renameBackup.value,
          );

      if (context.mounted) {
        Navigator.of(context).pop();
        showSnackBar(
          context,
          renamed ? 'Renamed to "$name"' : 'No "SaveName" property to rename',
        );
      }
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              Text(
                'Rename ${mod.modType.label}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
              Text(
                'Updates the "SaveName" inside the JSON file. The JSON file name is not changed.',
                style: TextStyle(fontSize: 16),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text('Name', style: TextStyle(fontSize: 16)),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    cursorColor: Colors.black,
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold),
                    onSubmitted: (_) {
                      if (!isRenaming.value) rename();
                    },
                    decoration: InputDecoration(
                      fillColor: Colors.white,
                      filled: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              if (hasBackup)
                CheckboxListTile(
                  value: renameBackup.value,
                  checkColor: Colors.black,
                  activeColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: isRenaming.value
                      ? null
                      : (value) => renameBackup.value = value ?? false,
                  title: Text(
                    'Rename the backup file to keep it matching this '
                    '${mod.modType.label}',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              Row(
                spacing: 8,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: isRenaming.value
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: isRenaming.value ? null : rename,
                    icon: Icon(Icons.drive_file_rename_outline),
                    label: const Text('Rename'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
