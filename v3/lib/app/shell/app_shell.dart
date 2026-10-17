import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/app_destination.dart';
import 'package:tts_mod_vault/app/shell/placeholders.dart';
import 'package:tts_mod_vault/app/shell/vault_sidebar.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Root layout: the [VaultSidebar] on the left and the current destination's
/// page filling the rest.
class AppShell extends ConsumerWidget {
  /// Creates the shell.
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = ref.watch(appDestinationProvider);
    final operationRunning = ref.watch(operationRunningProvider);
    final l10n = AppLocalizations.of(context);
    final enabled = !operationRunning;

    void notImplemented() => showAppSnackBar(context, l10n.notImplementedYet);

    return Scaffold(
      body: Row(
        children: [
          VaultSidebar(
            selected: destination,
            destinationsEnabled: enabled,
            onDestinationSelected: ref
                .read(appDestinationProvider.notifier)
                .select,
            actionGroups: [
              [
                SidebarAction(
                  icon: Icons.refresh,
                  label: l10n.actionRefresh,
                  enabled: enabled,
                  onPressed: notImplemented,
                ),
                SidebarAction(
                  icon: Icons.cleaning_services_outlined,
                  label: l10n.actionCleanup,
                  enabled: enabled,
                  onPressed: notImplemented,
                ),
              ],
              [
                SidebarAction(
                  icon: Icons.unarchive_outlined,
                  label: l10n.actionImportBackups,
                  enabled: enabled,
                  onPressed: notImplemented,
                ),
                SidebarAction(
                  icon: Icons.upload_file_outlined,
                  label: l10n.actionImportJson,
                  enabled: enabled,
                  onPressed: notImplemented,
                ),
                SidebarAction(
                  icon: Icons.download_outlined,
                  label: l10n.actionDownloadWorkshopMods,
                  enabled: enabled,
                  onPressed: notImplemented,
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
          Expanded(
            child: switch (destination) {
              AppDestination.mods => const ModsPage(),
              AppDestination.backups => const BackupsPage(),
            },
          ),
        ],
      ),
    );
  }
}
