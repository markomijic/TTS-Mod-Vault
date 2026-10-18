import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart';
import 'package:tts_mod_vault/features/backups/presentation/file_picker_service.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 640;

/// Shows the [ImportJsonDialog].
Future<void> showImportJsonDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const ImportJsonDialog(),
);

/// Port of 2.x `ImportJsonDialog`: pick a `.json` file and optionally a
/// `.png`, choose what to import it as (mod / save / saved object, which
/// selects the Workshop, Saves or Saved Objects folder) with a folder
/// override, then Import closes the dialog and runs
/// `BackupService.importJson`; the outcome is a snack bar.
class ImportJsonDialog extends HookConsumerWidget {
  /// Creates the dialog.
  const ImportJsonDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final directories = ref.watch(directoriesProvider).value;

    final jsonPath = useState<String?>(null);
    final pngPath = useState<String?>(null);
    final type = useState(ModType.mod);
    final folderOverride = useState<String?>(null);

    final folder =
        folderOverride.value ?? defaultImportFolder(directories, type.value);
    final json = jsonPath.value;
    final png = pngPath.value;
    final canImport = json != null && folder != null && folder.isNotEmpty;

    Future<void> pickJson() async {
      final picker = ref.read(filePickerServiceProvider);
      try {
        final picked = await picker.pickJsonFile(
          dialogTitle: l10n.importJsonPickTitle,
        );
        if (picked != null) jsonPath.value = p.normalize(picked);
      } on Object {
        if (context.mounted) {
          showAppSnackBar(context, l10n.couldNotOpenFilePicker);
        }
      }
    }

    Future<void> pickPng() async {
      final picker = ref.read(filePickerServiceProvider);
      try {
        final picked = await picker.pickPngFile(
          dialogTitle: l10n.importJsonPickImageTitle,
        );
        if (picked != null) pngPath.value = p.normalize(picked);
      } on Object {
        if (context.mounted) {
          showAppSnackBar(context, l10n.couldNotOpenFilePicker);
        }
      }
    }

    Future<void> pickFolder() async {
      final picker = ref.read(directoryPickerProvider);
      try {
        final picked = await picker.pickDirectory(
          dialogTitle: l10n.workshopSelectFolder,
          initialDirectory: folder == null || folder.isEmpty ? null : folder,
        );
        if (picked != null) folderOverride.value = p.normalize(picked);
      } on Object {
        if (context.mounted) {
          showAppSnackBar(context, l10n.couldNotOpenFolderPicker);
        }
      }
    }

    Future<void> import() async {
      if (!canImport) return;
      final ui = OperationUi.of(context);
      final service = ref.read(backupServiceProvider);
      final fileName = p.basename(json);
      Navigator.of(context).pop();
      try {
        final result = await ui.launch(
          () => service.importJson(
            sourceJson: json,
            destinationFolder: folder,
            type: type.value,
            sourcePng: png,
          ),
        );
        if (result == null) return;
        ui.showSnackBar(l10n.importJsonDone(fileName));
      } on Object catch (error) {
        ui.showSnackBar(l10n.importFailed(error.toString()));
      }
    }

    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return AppDialog(
      title: l10n.importJsonTitle,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.importJsonHint),
            Gaps.h16,
            _FileRow(
              label: l10n.importJsonFileLabel,
              value: json == null ? l10n.importJsonNoFile : p.basename(json),
              picked: json != null,
              button: FilledButton.tonalIcon(
                onPressed: pickJson,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(l10n.importJsonSelectJson),
              ),
            ),
            Gaps.h12,
            _FileRow(
              label: l10n.importJsonImageLabel,
              value: png == null ? l10n.importJsonNoFile : p.basename(png),
              picked: png != null,
              button: FilledButton.tonalIcon(
                onPressed: pickPng,
                icon: const Icon(Icons.image_outlined),
                label: Text(l10n.importJsonSelectImage),
              ),
              trailing: png == null
                  ? null
                  : IconButton(
                      tooltip: l10n.importJsonClearImage,
                      icon: const Icon(Icons.clear),
                      onPressed: () => pngPath.value = null,
                    ),
            ),
            if (json != null && png != null) ...[
              Gaps.h4,
              Text(
                l10n.importJsonImageSavedAs(
                  '${p.basenameWithoutExtension(json)}.png',
                ),
                style: mutedStyle,
              ),
            ],
            Gaps.h16,
            Text(
              l10n.importJsonTypeLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Gaps.h8,
            SegmentedButton<ModType>(
              showSelectedIcon: false,
              segments: [
                for (final t in ModType.values)
                  ButtonSegment(value: t, label: Text(t.title(l10n))),
              ],
              selected: {type.value},
              onSelectionChanged: (selection) {
                type.value = selection.single;
                folderOverride.value = null;
              },
            ),
            Gaps.h16,
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.importJsonDestination(folder ?? ''),
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
          onPressed: canImport ? import : null,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(l10n.importAction),
        ),
      ],
    );
  }
}

/// The folder a JSON of [type] goes to by default: `Mods/Workshop`,
/// `Saves` or `Saves/Saved Objects`; null while the directories load.
String? defaultImportFolder(Directories? directories, ModType type) {
  if (directories == null) return null;
  return switch (type) {
    ModType.mod => directories.workshopDir,
    ModType.save => directories.savesDir,
    ModType.savedObject => directories.savedObjectsDir,
  };
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.label,
    required this.value,
    required this.picked,
    required this.button,
    this.trailing,
  });

  final String label;
  final String value;
  final bool picked;
  final Widget button;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = this.trailing;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Gaps.h4,
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: picked ? null : theme.colorScheme.onSurfaceVariant,
                  fontStyle: picked ? null : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
        Gaps.w8,
        button,
      ],
    );
  }
}
