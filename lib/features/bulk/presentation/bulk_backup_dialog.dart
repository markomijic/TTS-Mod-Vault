import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart'
    show BulkBackupBehavior, PostBackupDeletion;
import 'package:tts_mod_vault/features/bulk/presentation/bulk_labels.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 560;

/// What the user picked in the [BulkBackupDialog].
@immutable
final class BulkBackupChoice {
  /// Creates a choice.
  const BulkBackupChoice({
    required this.folder,
    required this.behavior,
    required this.postBackupDeletion,
    required this.setAsDefaultFolder,
  });

  /// Folder every archive is written into.
  final String folder;

  /// What to do with mods that already have a backup.
  final BulkBackupBehavior behavior;

  /// What to do with each mod's cached files afterwards.
  final PostBackupDeletion postBackupDeletion;

  /// Whether [folder] becomes the default backups folder.
  final bool setAsDefaultFolder;
}

/// Shows the [BulkBackupDialog]; null when cancelled.
Future<BulkBackupChoice?> showBulkBackupDialog(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<BulkBackupChoice>(
  context: context,
  builder: (_) => BulkBackupDialog(title: title, message: message),
);

/// Port of 2.x `BulkBackupDialog`: the target folder (the default backups
/// folder, or one picked here), the behaviour for mods that already have
/// a backup, the post-backup deletion and, when the folder is not the
/// default one, "use as default". Confirm is disabled until a folder is
/// chosen. Used by Backup and Download & backup.
class BulkBackupDialog extends HookConsumerWidget {
  /// Creates the dialog.
  const BulkBackupDialog({
    super.key,
    required this.title,
    required this.message,
    this.initialBehavior = BulkBackupBehavior.replaceIfOutOfDate,
  });

  /// Dialog title (the action's name).
  final String title;

  /// First line, stating how many mods are affected.
  final String message;

  /// Behaviour preselected in the radio group.
  final BulkBackupBehavior initialBehavior;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = VaultColors.of(context);
    final backupsDir = ref.watch(
      directoriesProvider.select((d) => d.value?.backupsDir ?? ''),
    );
    final pickedFolder = useState<String?>(null);
    final behavior = useState(initialBehavior);
    final deletion = useState(PostBackupDeletion.none);
    final setAsDefault = useState(false);

    final folder = pickedFolder.value ?? backupsDir;
    final hasFolder = folder.isNotEmpty;
    final offerDefault = hasFolder && !p.equals(folder, backupsDir);

    Future<void> pickFolder() async {
      try {
        final picked = await ref
            .read(directoryPickerProvider)
            .pickDirectory(
              dialogTitle: l10n.backupPickFolderTitle,
              initialDirectory: hasFolder ? folder : null,
            );
        if (picked != null) pickedFolder.value = p.normalize(picked);
      } on Object {
        if (context.mounted) {
          showAppSnackBar(context, l10n.couldNotOpenFolderPicker);
        }
      }
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.xs),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    return AppDialog(
      title: title,
      content: SizedBox(
        width: _dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              heading(l10n.bulkBackupFolderLabel),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasFolder ? folder : l10n.bulkBackupFolderNone,
                      style: hasFolder
                          ? theme.textTheme.bodyMedium
                          : theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                    ),
                  ),
                  Gaps.w8,
                  OutlinedButton.icon(
                    onPressed: pickFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(l10n.bulkBackupSelectFolder),
                  ),
                ],
              ),
              if (offerDefault)
                CheckboxListTile(
                  value: setAsDefault.value,
                  onChanged: (value) => setAsDefault.value = value ?? false,
                  title: Text(l10n.backupSetDefaultFolder),
                  secondary: Tooltip(
                    message: l10n.backupSetDefaultFolderInfo,
                    child: Icon(
                      Icons.info_outline,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              heading(l10n.bulkBackupExistingLabel),
              RadioGroup<BulkBackupBehavior>(
                groupValue: behavior.value,
                onChanged: (value) {
                  if (value != null) behavior.value = value;
                },
                child: Column(
                  children: [
                    for (final option in BulkBackupBehavior.values)
                      RadioListTile<BulkBackupBehavior>(
                        value: option,
                        title: Text(option.title(l10n)),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
              heading(l10n.bulkBackupAfterLabel),
              RadioGroup<PostBackupDeletion>(
                groupValue: deletion.value,
                onChanged: (value) {
                  if (value != null) deletion.value = value;
                },
                child: Column(
                  children: [
                    for (final option in PostBackupDeletion.values)
                      RadioListTile<PostBackupDeletion>(
                        value: option,
                        title: Text(option.title(l10n)),
                        secondary: option == PostBackupDeletion.deleteAllAssets
                            ? Tooltip(
                                message: l10n.sharedFilesWarning,
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  color: colors.logWarning,
                                ),
                              )
                            : null,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: hasFolder
              ? () => Navigator.of(context).pop(
                  BulkBackupChoice(
                    folder: folder,
                    behavior: behavior.value,
                    postBackupDeletion: deletion.value,
                    setAsDefaultFolder: offerDefault && setAsDefault.value,
                  ),
                )
              : null,
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}
