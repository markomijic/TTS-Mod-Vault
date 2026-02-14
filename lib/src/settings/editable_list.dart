import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;
import 'package:tts_mod_vault/src/settings/settings_dialog.dart'
    show SectionHeader;

class EditableStringList extends StatelessWidget {
  final String title;
  final String tooltipMessage;
  final List<String> values;
  final void Function(List<String>) onChanged;
  final String addLabel;
  final String? hint;

  const EditableStringList({
    super.key,
    required this.title,
    required this.tooltipMessage,
    required this.values,
    required this.onChanged,
    required this.addLabel,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 4,
          children: [
            SectionHeader(title: title),
            CustomTooltip(
              message: tooltipMessage,
              child: Icon(Icons.info_outline),
            ),
          ],
        ),
        ...values.asMap().entries.map((entry) {
          final index = entry.key;
          final value = entry.value;

          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              value,
              style: TextStyle(fontSize: 16),
            ),
            trailing: Row(
              spacing: 8,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.edit_outlined, size: 24),
                  onPressed: () async {
                    final result = await _editDialog(context, value, "Edit");
                    if (result != null) {
                      final newList = List<String>.from(values);
                      newList[index] = result;
                      onChanged(newList);
                    }
                  },
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.delete_outline, size: 24),
                  onPressed: () {
                    final newList = List<String>.from(values);
                    newList.removeAt(index);
                    onChanged(newList);
                  },
                ),
                SizedBox.shrink(),
              ],
            ),
          );
        }),
        ElevatedButton.icon(
          onPressed: () async {
            final result = await _editDialog(context, '', 'Add');
            if (result != null) {
              onChanged([...values, result]);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(addLabel),
        ),
      ],
    );
  }

  Future<String?> _editDialog(
      BuildContext context, String initial, String title) async {
    final controller = TextEditingController(text: initial);

    return showDialog<String>(
      context: context,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: controller,
              autofocus: true,
              cursorColor: Colors.black,
              keyboardType: TextInputType.number,
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                hintText: hint,
                hintStyle: TextStyle(color: Colors.black),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(context, text);
              },
              icon: Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
