/// The Features section of the Settings dialog: the seven behaviour
/// switches of v2 (check for updates, saved objects, backup state, forced
/// JSON name, audio exclusion, custom Saves folder, PDF thumbnails).
library;

import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';
import 'package:tts_mod_vault/features/settings/presentation/settings_widgets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Edits the feature switches of [draft].
class FeaturesSection extends StatelessWidget {
  /// Creates the section.
  const FeaturesSection({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  /// The settings being edited.
  final AppSettings draft;

  /// Receives the edited settings.
  final ValueChanged<AppSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSwitchTile(
            title: l10n.settingCheckForUpdates,
            value: draft.checkForUpdatesOnStart,
            onChanged: (v) =>
                onChanged(draft.copyWith(checkForUpdatesOnStart: v)),
          ),
          SettingsSwitchTile(
            title: l10n.settingShowSavedObjects,
            info: l10n.settingShowSavedObjectsInfo,
            value: draft.showSavedObjects,
            onChanged: (v) => onChanged(draft.copyWith(showSavedObjects: v)),
          ),
          SettingsSwitchTile(
            title: l10n.settingShowBackupState,
            info: l10n.settingShowBackupStateInfo,
            value: draft.showBackupState,
            onChanged: (v) => onChanged(draft.copyWith(showBackupState: v)),
          ),
          SettingsSwitchTile(
            title: l10n.settingForceBackupJsonFilename,
            info: l10n.settingForceBackupJsonFilenameInfo,
            value: draft.forceBackupJsonFilename,
            onChanged: (v) =>
                onChanged(draft.copyWith(forceBackupJsonFilename: v)),
          ),
          SettingsSwitchTile(
            title: l10n.settingIgnoreAudio,
            info: l10n.settingIgnoreAudioInfo,
            value: draft.ignoreAudioAssets,
            onChanged: (v) => onChanged(draft.copyWith(ignoreAudioAssets: v)),
          ),
          SettingsSwitchTile(
            title: l10n.settingAllowCustomSaves,
            info: l10n.settingAllowCustomSavesInfo,
            value: draft.allowCustomSavesFolder,
            onChanged: (v) =>
                onChanged(draft.copyWith(allowCustomSavesFolder: v)),
          ),
          SettingsSwitchTile(
            title: l10n.settingShowPdfThumbnails,
            info: l10n.settingShowPdfThumbnailsInfo,
            value: draft.showPdfThumbnails,
            onChanged: (v) => onChanged(draft.copyWith(showPdfThumbnails: v)),
          ),
        ],
      ),
    );
  }
}
