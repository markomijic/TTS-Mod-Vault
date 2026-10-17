import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// "Import selected (N)" where N is the number of backups the import would
/// apply to: the selection when any backup is selected, otherwise every
/// backup that passes the current search and filters.
///
/// Phase 4 stub: pressing it shows the not-implemented snack bar; the bulk
/// import replaces the callback.
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
    final count = selectedCount > 0 ? selectedCount : filteredCount;
    final label = l10n.importSelectedBackups(count);

    return FilledButton.tonalIcon(
      onPressed: () => showNotImplemented(context, label),
      icon: const Icon(Icons.unarchive_outlined),
      label: Text(label),
    );
  }
}
