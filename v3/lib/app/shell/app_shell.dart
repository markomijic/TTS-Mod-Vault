import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart';
import 'package:tts_mod_vault/app/shell/vault_sidebar.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/features/about/presentation/update_notice.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_actions.dart';
import 'package:tts_mod_vault/features/backups/presentation/import_json_dialog.dart';
import 'package:tts_mod_vault/features/cleanup/presentation/cleanup_actions.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/presentation/library_page.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_progress_bar.dart';
import 'package:tts_mod_vault/features/workshop/presentation/download_workshop_mods_dialog.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Root layout: the [VaultSidebar] (actions only) on the left and the one
/// [LibraryPage] filling the rest, with the [OperationProgressBar] docked
/// under its list so a running operation is visible on every tab. Mods,
/// saves, saved objects and backups are tabs of the page, not destinations.
/// The [UpdateNotice] around it shows the new-version dialog once the
/// GitHub release check answers.
class AppShell extends ConsumerWidget {
  /// Creates the shell.
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operationRunning = ref.watch(operationRunningProvider);
    final l10n = AppLocalizations.of(context);
    final enabled = !operationRunning;

    void notImplemented() => showAppSnackBar(context, l10n.notImplementedYet);

    Future<void> refresh() async {
      final clearCache = await showConfirmDialogWithCheckbox(
        context,
        title: l10n.refreshDialogTitle,
        checkboxLabel: l10n.refreshClearCacheLabel,
        checkboxInfo: l10n.refreshClearCacheInfo,
        confirmLabel: l10n.actionRefresh,
      );
      if (clearCache == null) return;
      await ref
          .read(libraryControllerProvider.notifier)
          .refresh(clearCache: clearCache);
    }

    return UpdateNotice(
      child: Scaffold(
        body: Row(
          children: [
            VaultSidebar(
              actionGroups: [
                [
                  SidebarAction(
                    icon: Icons.refresh,
                    label: l10n.actionRefresh,
                    enabled: enabled,
                    onPressed: refresh,
                  ),
                  SidebarAction(
                    icon: Icons.cleaning_services_outlined,
                    label: l10n.actionCleanup,
                    enabled: enabled,
                    onPressed: () => runCleanup(context, ref),
                  ),
                ],
                [
                  SidebarAction(
                    icon: Icons.unarchive_outlined,
                    label: l10n.actionImportBackups,
                    enabled: enabled,
                    onPressed: () => importBackupsFromPicker(context, ref),
                  ),
                  SidebarAction(
                    icon: Icons.upload_file_outlined,
                    label: l10n.actionImportJson,
                    enabled: enabled,
                    onPressed: () => showImportJsonDialog(context),
                  ),
                  SidebarAction(
                    icon: Icons.download_outlined,
                    label: l10n.actionDownloadWorkshopMods,
                    enabled: enabled,
                    onPressed: () => showDownloadWorkshopModsDialog(context),
                  ),
                ],
              ],
              footerActions: [
                SidebarAction(
                  icon: Icons.help_outline,
                  label: l10n.actionHelp,
                  enabled: enabled,
                  onPressed: notImplemented,
                ),
                SidebarAction(
                  icon: Icons.settings_outlined,
                  label: l10n.actionSettings,
                  enabled: enabled,
                  onPressed: notImplemented,
                ),
              ],
            ),
            const Expanded(
              child: LibraryPage(bottomSlot: OperationProgressBar()),
            ),
          ],
        ),
      ),
    );
  }
}
