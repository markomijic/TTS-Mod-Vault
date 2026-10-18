/// A titled list of strings with edit / remove buttons per row and an add
/// button; entries are edited in a small text dialog. Port of v2
/// `EditableStringList`, used for the excluded subfolders and domains.
library;

import 'package:flutter_hooks/flutter_hooks.dart'
    show HookWidget, useTextEditingController;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/settings/presentation/settings_widgets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the entry editor dialog.
const double _editorWidth = 420;

/// An editable list of strings.
class EditableStringList extends StatelessWidget {
  /// Creates the list.
  const EditableStringList({
    super.key,
    required this.title,
    required this.values,
    required this.onChanged,
    required this.addLabel,
    this.info,
    this.hint,
  });

  /// Title above the list.
  final String title;

  /// Optional tooltip text of an info icon after the title.
  final String? info;

  /// Current entries.
  final List<String> values;

  /// Called with the new list after an add, edit or remove.
  final ValueChanged<List<String>> onChanged;

  /// Label of the add button.
  final String addLabel;

  /// Optional hint of the editor's text field.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    Future<void> edit(int? index) async {
      final result = await showEditableListEntryDialog(
        context,
        title: index == null
            ? l10n.editableListAddTitle
            : l10n.editableListEditTitle,
        initial: index == null ? '' : values[index],
        hint: hint,
      );
      if (result == null) return;
      final next = List<String>.of(values);
      if (index == null) {
        next.add(result);
      } else {
        next[index] = result;
      }
      onChanged(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(title, info: info),
        if (values.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.sm),
            child: Text(
              l10n.editableListEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (var i = 0; i < values.length; i++)
            ListTile(
              key: ValueKey('editable-$i-${values[i]}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(values[i], overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.edit,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => edit(i),
                  ),
                  IconButton(
                    tooltip: l10n.remove,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        onChanged(List<String>.of(values)..removeAt(i)),
                  ),
                ],
              ),
            ),
        Gaps.h4,
        OutlinedButton.icon(
          onPressed: () => edit(null),
          icon: const Icon(Icons.add),
          label: Text(addLabel),
        ),
      ],
    );
  }
}

/// Asks for one text entry; returns the trimmed text or null on Cancel.
/// Blank text cannot be saved.
Future<String?> showEditableListEntryDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
}) => showDialog<String>(
  context: context,
  builder: (_) => _EntryDialog(title: title, initial: initial, hint: hint),
);

class _EntryDialog extends HookWidget {
  const _EntryDialog({required this.title, required this.initial, this.hint});

  final String title;
  final String initial;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = useTextEditingController(text: initial);

    void submit() {
      final text = controller.text.trim();
      if (text.isEmpty) return;
      Navigator.of(context).pop(text);
    }

    return AppDialog(
      title: title,
      content: SizedBox(
        width: _editorWidth,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: hint,
          ),
          onSubmitted: (_) => submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: submit, child: Text(l10n.save)),
      ],
    );
  }
}
