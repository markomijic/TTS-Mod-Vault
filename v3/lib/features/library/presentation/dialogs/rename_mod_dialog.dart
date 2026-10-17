import 'package:flutter_hooks/flutter_hooks.dart'
    show useListenable, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/core/result/result.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/mod_edit_service.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 480;

/// Opens the rename dialog for [mod]; completes when it closes.
Future<void> showRenameModDialog(BuildContext context, Mod mod) =>
    showDialog<void>(
      context: context,
      builder: (_) => RenameModDialog(mod: mod),
    );

/// Dialog that rewrites a mod's `SaveName`.
///
/// The field is prefilled with the display name; Rename is enabled when the
/// trimmed text is non-empty and differs from the current name. When the mod
/// has a backup, a checkbox (on by default) also renames the archive. The
/// result is reported in a snack bar; on failure the dialog stays open and,
/// for saved objects, explains that only mods and saves carry a `SaveName`.
/// Port of 2.x `RenameModDialog`.
class RenameModDialog extends HookConsumerWidget {
  /// Creates the dialog for [mod].
  const RenameModDialog({super.key, required this.mod});

  /// The mod to rename.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final type = mod.ref.type;
    final hasBackup = mod.backup != null;

    final controller = useTextEditingController(text: mod.displayName);
    final text = useListenable(controller).text;
    final renameBackup = useState(true);
    final busy = useState(false);
    final failure = useState<Failure?>(null);

    final name = text.trim();
    final isEmpty = name.isEmpty;
    final canSubmit = !busy.value && !isEmpty && name != mod.displayName;

    Future<void> submit() async {
      if (!canSubmit) return;
      busy.value = true;
      failure.value = null;
      final result = await ref
          .read(modEditServiceProvider)
          .renameMod(mod, name, renameBackup: hasBackup && renameBackup.value);
      if (!context.mounted) return;
      switch (result) {
        case Ok():
          Navigator.of(context).pop();
          showAppSnackBar(context, l10n.renamedTo(name));
        case Err(failure: final f):
          busy.value = false;
          failure.value = f;
          showAppSnackBar(context, f.message);
      }
    }

    final Failure? error = failure.value;

    return AppDialog(
      title: l10n.renameDialogTitle(type.singular(l10n)),
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.renameDialogHint),
            Gaps.h16,
            TextField(
              controller: controller,
              autofocus: true,
              enabled: !busy.value,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: l10n.renameNameLabel,
                border: const OutlineInputBorder(),
                errorText: isEmpty ? l10n.renameNameEmpty : null,
              ),
            ),
            if (hasBackup) ...[
              Gaps.h8,
              CheckboxListTile(
                value: renameBackup.value,
                onChanged: busy.value
                    ? null
                    : (value) => renameBackup.value = value ?? false,
                title: Text(l10n.renameAlsoBackup),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
            if (error != null) ...[
              Gaps.h16,
              Text(
                type == ModType.savedObject
                    ? l10n.renameSavedObjectNote
                    : error.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy.value ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: canSubmit ? submit : null,
          icon: const Icon(Icons.drive_file_rename_outline),
          label: Text(l10n.renameAction),
        ),
      ],
    );
  }
}
