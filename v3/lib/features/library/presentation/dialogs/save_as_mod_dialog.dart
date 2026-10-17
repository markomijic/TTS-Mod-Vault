import 'package:flutter_hooks/flutter_hooks.dart'
    show useListenable, useMemoized, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/mod_edit_service.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 560;

/// Characters that are not allowed in a file name on any supported OS,
/// plus ASCII control characters.
final RegExp _invalidFileNameChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

/// Turns a save name into a usable JSON base name: forbidden characters
/// are dropped, whitespace is collapsed, trailing dots and spaces (which
/// Windows strips) are removed. Falls back to [fallback] when nothing is
/// left.
String sanitizeFileName(String name, {required String fallback}) {
  final cleaned = name
      .replaceAll(_invalidFileNameChars, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  return cleaned.isEmpty ? fallback : cleaned;
}

/// Whether [name] is a valid JSON base name: non-empty and free of
/// forbidden characters.
bool isValidFileName(String name) =>
    name.isNotEmpty && !_invalidFileNameChars.hasMatch(name);

/// Opens the Save as Mod dialog for [save]; completes when it closes.
Future<void> showSaveAsModDialog(BuildContext context, Mod save) =>
    showDialog<void>(
      context: context,
      builder: (_) => SaveAsModDialog(save: save),
    );

/// Dialog that copies a save into a mods folder so it appears as a mod.
///
/// The target folder defaults to `Mods/Workshop` and can be typed or picked
/// with Browse; the file name is prefilled with the sanitised display name
/// and shown with a fixed `.json` suffix. The outcome is reported in a
/// snack bar. Port of 2.x `SaveAsModDialog`.
class SaveAsModDialog extends HookConsumerWidget {
  /// Creates the dialog for [save].
  const SaveAsModDialog({super.key, required this.save});

  /// The save to copy.
  final Mod save;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    final defaultFolder = useMemoized(() {
      final directories = ref.read(directoriesProvider).value;
      return directories == null ? '' : p.normalize(directories.workshopDir);
    });
    final folderController = useTextEditingController(text: defaultFolder);
    final fileNameController = useTextEditingController(
      text: sanitizeFileName(save.displayName, fallback: save.id),
    );
    final folder = useListenable(folderController).text.trim();
    final fileName = useListenable(fileNameController).text.trim();
    final busy = useState(false);

    final folderError = folder.isEmpty ? l10n.saveAsModFolderEmpty : null;
    final fileNameError = fileName.isEmpty
        ? l10n.saveAsModFileNameEmpty
        : !isValidFileName(fileName)
        ? l10n.saveAsModFileNameInvalid
        : null;
    final canSubmit =
        !busy.value && folderError == null && fileNameError == null;

    Future<void> browse() async {
      final String? picked;
      try {
        picked = await ref
            .read(directoryPickerProvider)
            .pickDirectory(
              dialogTitle: l10n.saveAsModFolderLabel,
              initialDirectory: folder.isEmpty ? null : folder,
            );
      } on Object catch (_) {
        if (context.mounted) showAppSnackBar(context, l10n.filePickerFailed);
        return;
      }
      if (picked != null) folderController.text = p.normalize(picked);
    }

    Future<void> submit() async {
      if (!canSubmit) return;
      busy.value = true;
      final result = await ref
          .read(modEditServiceProvider)
          .saveAsMod(save, targetFolder: folder, fileName: fileName);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        result.when(
          ok: (_) => l10n.savedAsMod(save.displayName),
          err: (failure) => failure.message,
        ),
      );
    }

    return AppDialog(
      title: l10n.menuSaveAsMod,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.saveAsModHint),
            Gaps.h16,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: folderController,
                    enabled: !busy.value,
                    decoration: InputDecoration(
                      labelText: l10n.saveAsModFolderLabel,
                      border: const OutlineInputBorder(),
                      errorText: folderError,
                    ),
                  ),
                ),
                Gaps.w8,
                Padding(
                  padding: const EdgeInsets.only(top: Insets.xs),
                  child: OutlinedButton.icon(
                    onPressed: busy.value ? null : browse,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(l10n.browse),
                  ),
                ),
              ],
            ),
            Gaps.h16,
            TextField(
              controller: fileNameController,
              autofocus: true,
              enabled: !busy.value,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: l10n.saveAsModFileNameLabel,
                border: const OutlineInputBorder(),
                suffixText: '.json',
                errorText: fileNameError,
              ),
            ),
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
          icon: const Icon(Icons.drive_file_move_outlined),
          label: Text(l10n.menuSaveAsMod),
        ),
      ],
    );
  }
}
