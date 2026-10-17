import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_context_menu.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/item_interaction_region.dart';

/// [ItemInteractionRegion] bound to [backupSelectionProvider] and the backup
/// context menu: left click selects the backup, Ctrl/Cmd + left click
/// toggles it in the multi-selection, right click selects it and opens the
/// menu.
class BackupInteractionRegion extends ConsumerWidget {
  /// Creates the region for [backup].
  const BackupInteractionRegion({
    super.key,
    required this.backup,
    required this.builder,
  });

  /// The backup this card or row shows.
  final Backup backup;

  /// Builds the visual.
  final ItemInteractionBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = backup.path;
    final selection = ref.read(backupSelectionProvider.notifier);
    return ItemInteractionRegion(
      selected: backupSelectionProvider.select((s) => s.contains(path)),
      onSelect: () => selection.select(path),
      onToggle: () => selection.toggle(path),
      onContextMenu: (position) =>
          showBackupContextMenu(context, ref, position, backup),
      builder: builder,
    );
  }
}
