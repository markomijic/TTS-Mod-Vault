/// The Interface section of the Settings dialog: list/grid defaults, card
/// titles, the language, default sorts and the asset URL font size.
library;

import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/sort_filter.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_labels.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';
import 'package:tts_mod_vault/features/settings/presentation/settings_widgets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';
import 'package:tts_mod_vault/l10n/locale_tags.dart';

/// Edits the interface settings of [draft].
class InterfaceSection extends StatelessWidget {
  /// Creates the section.
  const InterfaceSection({
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
    // A stored language that is no longer supported shows as the system
    // default, the way the app resolves it.
    final tags = {
      for (final locale in AppLocalizations.supportedLocales) localeTag(locale),
    };
    final selectedLanguage = tags.contains(draft.locale) ? draft.locale : null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSwitchTile(
            title: l10n.settingModsListView,
            value: draft.useModsListView,
            onChanged: (v) => onChanged(draft.copyWith(useModsListView: v)),
          ),
          SettingsSwitchTile(
            title: l10n.settingBackupsListView,
            value: draft.useBackupsListView,
            onChanged: (v) => onChanged(draft.copyWith(useBackupsListView: v)),
          ),
          SettingsSwitchTile(
            title: l10n.settingShowTitleOnCards,
            value: draft.showTitleOnCards,
            onChanged: (v) => onChanged(draft.copyWith(showTitleOnCards: v)),
          ),
          SettingsLabeledRow(
            title: l10n.settingLanguage,
            trailing: DropdownButton<String?>(
              key: const Key('settings-language'),
              value: selectedLanguage,
              items: [
                DropdownMenuItem(
                  child: Text(l10n.settingLanguageSystemDefault),
                ),
                for (final locale in AppLocalizations.supportedLocales)
                  DropdownMenuItem(
                    value: localeTag(locale),
                    child: Text(nativeLanguageName(locale)),
                  ),
              ],
              onChanged: (tag) => onChanged(draft.copyWith(locale: () => tag)),
            ),
          ),
          SettingsLabeledRow(
            title: l10n.settingDefaultModSort,
            trailing: DropdownButton<ModSortOption>(
              key: const Key('settings-default-mod-sort'),
              value: draft.defaultSortOption,
              items: [
                for (final option in ModSortOption.values)
                  DropdownMenuItem(
                    value: option,
                    child: Text(option.label(l10n)),
                  ),
              ],
              onChanged: (option) {
                if (option != null) {
                  onChanged(draft.copyWith(defaultSortOption: option));
                }
              },
            ),
          ),
          SettingsLabeledRow(
            title: l10n.settingDefaultBackupSort,
            trailing: DropdownButton<BackupSortOption>(
              key: const Key('settings-default-backup-sort'),
              value: draft.defaultBackupSortOption,
              items: [
                for (final option in BackupSortOption.values)
                  DropdownMenuItem(
                    value: option,
                    child: Text(option.label(l10n)),
                  ),
              ],
              onChanged: (option) {
                if (option != null) {
                  onChanged(draft.copyWith(defaultBackupSortOption: option));
                }
              },
            ),
          ),
          SettingsLabeledRow(
            title: l10n.settingAssetUrlFontSize,
            info: l10n.settingAssetUrlFontSizeInfo(
              formatSettingsNumber(AppSettings.minAssetUrlFontSize),
              formatSettingsNumber(AppSettings.maxAssetUrlFontSize),
              formatSettingsNumber(AppSettings.defaultAssetUrlFontSize),
            ),
            trailing: SettingsNumberField(
              key: const Key('settings-url-font-size'),
              value: draft.assetUrlFontSize,
              min: AppSettings.minAssetUrlFontSize,
              max: AppSettings.maxAssetUrlFontSize,
              decimals: true,
              onChanged: (v) => onChanged(draft.copyWith(assetUrlFontSize: v)),
            ),
          ),
        ],
      ),
    );
  }
}
