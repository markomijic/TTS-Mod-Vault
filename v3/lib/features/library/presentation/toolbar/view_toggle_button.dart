import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Switches between the grid and the list; the choice is a setting
/// (`AppSettings.useModsListView` / `useBackupsListView`) written through
/// `SettingsController.update`, so the Settings dialog and the toolbar
/// always agree. The mod tabs share one flag, the Backups tab has its own.
class ViewToggleButton extends ConsumerWidget {
  /// Creates the button.
  const ViewToggleButton({super.key, this.backups = false});

  /// Whether the button drives the Backups tab's flag.
  final bool backups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final useList = ref.watch(
      backups
          ? useBackupsListViewSettingProvider
          : useModsListViewSettingProvider,
    );
    return IconButton.outlined(
      tooltip: useList ? l10n.viewAsGrid : l10n.viewAsList,
      icon: Icon(useList ? Icons.grid_view_outlined : Icons.view_list_outlined),
      onPressed: () {
        final settings = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .update(
              backups
                  ? settings.copyWith(useBackupsListView: !useList)
                  : settings.copyWith(useModsListView: !useList),
            );
      },
    );
  }
}
