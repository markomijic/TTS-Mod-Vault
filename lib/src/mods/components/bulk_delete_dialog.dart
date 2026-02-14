import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/bulk_actions/bulk_actions_state.dart'
    show PostBackupDeletionEnum;

class BulkDeleteDialog extends HookConsumerWidget {
  final String title;
  final Function(PostBackupDeletionEnum deletionOption) onConfirm;

  const BulkDeleteDialog({
    super.key,
    required this.title,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDeletion =
        useState(PostBackupDeletionEnum.deleteNonSharedAssets);

    final options = PostBackupDeletionEnum.values
        .where((e) => e != PostBackupDeletionEnum.none)
        .toList();

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
                onPressed: () {
                  onConfirm.call(selectedDeletion.value);
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
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            Row(
              spacing: 8,
              children: [
                const Expanded(
                  child: Text('Shared assets:'),
                ),
                DropdownButton<PostBackupDeletionEnum>(
                  value: selectedDeletion.value,
                  dropdownColor: Colors.white,
                  style: TextStyle(color: Colors.white),
                  underline: Container(
                    height: 2,
                    color: Colors.white,
                  ),
                  focusColor: Colors.transparent,
                  selectedItemBuilder: (BuildContext context) {
                    return options.map<Widget>((item) {
                      return Container(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.label,
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList();
                  },
                  items: options.map((deletion) {
                    return DropdownMenuItem<PostBackupDeletionEnum>(
                      value: deletion,
                      child: Text(
                        deletion.label,
                        style: const TextStyle(color: Colors.black),
                      ),
                    );
                  }).toList(),
                  onChanged: (PostBackupDeletionEnum? newValue) {
                    if (newValue != null) {
                      selectedDeletion.value = newValue;
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
