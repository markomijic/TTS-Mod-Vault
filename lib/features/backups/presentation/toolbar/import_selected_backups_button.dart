import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_actions.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// "Import selected (N)" where N is the number of backups the import would
/// apply to: the selection when any backup is selected, otherwise every
/// backup that passes the current search and filters (after a confirmation
/// stating the count). Disabled while an operation runs or N is 0.
class ImportSelectedBackupsButton extends ConsumerWidget {
  /// Creates the button.
  const ImportSelectedBackupsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedCount = ref.watch(
      backupSelectionProvider.select((s) => s.length),
    );
    final filteredCount = ref.watch(
      filteredBackupsProvider.select((backups) => backups.length),
    );
    final running = ref.watch(operationRunningProvider);
    final count = selectedCount > 0 ? selectedCount : filteredCount;
    final label = l10n.importSelectedBackups(count);

    Future<void> import() async {
      if (selectedCount > 0) {
        await importBackups(context, ref, ref.read(selectedBackupsProvider));
        return;
      }
      final targets = ref.read(filteredBackupsProvider);
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.importAllListedTitle,
        message: l10n.importAllListedMessage(targets.length),
        confirmLabel: l10n.importAction,
      );
      if (!confirmed || !context.mounted) return;
      await importBackups(context, ref, targets);
    }

    return FilledButton.tonalIcon(
      onPressed: running || count == 0 ? null : import,
      icon: const Icon(Icons.unarchive_outlined),
      label: Text(label),
    );
  }
}
