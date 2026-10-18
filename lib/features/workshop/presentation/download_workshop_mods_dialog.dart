import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/features/workshop/application/workshop_service.dart';
import 'package:tts_mod_vault/features/workshop/presentation/workshop_id_parser.dart';
import 'package:tts_mod_vault/features/workshop/presentation/workshop_results_dialog.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog.
const double _dialogWidth = 700;

/// Lines of the id field.
const int _fieldLines = 4;

/// Shows the [DownloadWorkshopModsDialog].
Future<void> showDownloadWorkshopModsDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const DownloadWorkshopModsDialog(),
    );

/// Port of v2 `DownloadModsDialog`: a multi-line field that takes Workshop
/// ids or item URLs (see [parseWorkshopIds]), the number of ids
/// recognised, the target folder (the Workshop folder by default, with a
/// folder picker) and a Download button. Download closes the dialog and
/// starts `WorkshopService.downloadByIds`; the progress shows in the
/// docked progress bar and the [WorkshopDownloadResultsDialog] follows.
class DownloadWorkshopModsDialog extends HookConsumerWidget {
  /// Creates the dialog.
  const DownloadWorkshopModsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = useTextEditingController();
    final ids = useState(const <String>[]);
    final defaultDir = ref.watch(
      directoriesProvider.select((d) => d.value?.workshopDir),
    );
    final targetDir = useState<String?>(null);
    final folder = targetDir.value ?? defaultDir;

    Future<void> pickFolder() async {
      final picker = ref.read(directoryPickerProvider);
      String? picked;
      try {
        picked = await picker.pickDirectory(
          dialogTitle: l10n.workshopSelectFolder,
          initialDirectory: folder,
        );
      } on Object {
        if (context.mounted) {
          showAppSnackBar(context, l10n.couldNotOpenFolderPicker);
        }
        return;
      }
      if (picked == null || !context.mounted) return;
      targetDir.value = p.normalize(picked);
    }

    Future<void> download() async {
      final dir = folder;
      if (dir == null || ids.value.isEmpty) return;
      final ui = OperationUi.of(context);
      final service = ref.read(workshopServiceProvider);
      Navigator.of(context).pop();
      final result = await ui.launch(
        () => service.downloadByIds(ids.value, targetDir: dir),
      );
      if (result == null || !ui.mounted) return;
      await ui.showAppDialog<void>(
        (_) => WorkshopDownloadResultsDialog(result: result),
      );
    }

    final canDownload = ids.value.isNotEmpty && folder != null;

    return AppDialog(
      title: l10n.workshopDownloadTitle,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              minLines: _fieldLines,
              maxLines: _fieldLines,
              keyboardType: TextInputType.multiline,
              onChanged: (text) => ids.value = parseWorkshopIds(text),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: l10n.workshopDownloadHint,
              ),
            ),
            Gaps.h8,
            Text(
              l10n.workshopIdsRecognised(ids.value.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Gaps.h16,
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.workshopSaveTo(folder ?? ''),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Gaps.w8,
                OutlinedButton.icon(
                  onPressed: pickFolder,
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(l10n.workshopSelectFolder),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: canDownload ? download : null,
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.menuDownload),
        ),
      ],
    );
  }
}
