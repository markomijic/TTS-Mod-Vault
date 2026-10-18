import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/backups/application/backup_service.dart'
    show JsonConflictChoice, JsonImportConflict;
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart'
    show formatModDate;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 520;

/// Asks which JSON to keep when the local file is newer than the archive's
/// (port of 2.x `showJsonConflictDialog`): both save dates and asset
/// counts, a note that the assets are imported either way, and
/// Cancel / Use backup JSON file / Keep current JSON file. Dismissing the
/// dialog counts as Cancel.
Future<JsonConflictChoice> showJsonConflictDialog(
  BuildContext context,
  JsonImportConflict conflict,
) async {
  final choice = await showDialog<JsonConflictChoice>(
    context: context,
    builder: (_) => JsonConflictDialog(conflict: conflict),
  );
  return choice ?? JsonConflictChoice.cancel;
}

/// The dialog behind [showJsonConflictDialog]; pops with the choice.
class JsonConflictDialog extends StatelessWidget {
  /// Creates the dialog for [conflict].
  const JsonConflictDialog({super.key, required this.conflict});

  /// What is being decided.
  final JsonImportConflict conflict;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AppDialog(
      title: l10n.jsonConflictTitle,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.jsonConflictMessage(conflict.jsonFileName)),
            Gaps.h16,
            Text(
              l10n.jsonConflictCurrent(
                epochSecondsLabel(l10n, conflict.localEpoch),
                l10n.assetFilesCount(conflict.existingAssetCount),
              ),
            ),
            Gaps.h8,
            Text(
              l10n.jsonConflictBackup(
                epochSecondsLabel(l10n, conflict.backupEpoch),
                l10n.assetFilesCount(conflict.backupAssetCount),
              ),
            ),
            Gaps.h16,
            Text(
              l10n.jsonConflictNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(JsonConflictChoice.cancel),
          child: Text(l10n.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              Navigator.of(context).pop(JsonConflictChoice.useBackup),
          icon: const Icon(Icons.unarchive_outlined),
          label: Text(l10n.jsonConflictUseBackup),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(JsonConflictChoice.keepCurrent),
          icon: const Icon(Icons.shield_outlined),
          label: Text(l10n.jsonConflictKeepCurrent),
        ),
      ],
    );
  }
}

/// [epochSeconds] formatted with [formatModDate], or "N/A" when it is not a
/// positive timestamp.
String epochSecondsLabel(AppLocalizations l10n, int epochSeconds) {
  if (epochSeconds <= 0) return l10n.notAvailable;
  return formatModDate(
    l10n.localeName,
    DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000),
  );
}
