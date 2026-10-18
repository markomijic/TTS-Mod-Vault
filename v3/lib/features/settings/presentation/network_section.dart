/// The Network section of the Settings dialog: download concurrency and the
/// excluded domains.
library;

import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';
import 'package:tts_mod_vault/features/settings/presentation/editable_string_list.dart';
import 'package:tts_mod_vault/features/settings/presentation/settings_widgets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Edits the network settings of [draft].
class NetworkSection extends StatelessWidget {
  /// Creates the section.
  const NetworkSection({
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
          SettingsLabeledRow(
            title: l10n.settingConcurrentDownloads,
            info: l10n.settingConcurrentDownloadsInfo(
              AppSettings.maxConcurrentDownloads,
              AppSettings.defaultConcurrentDownloads,
            ),
            trailing: SettingsNumberField(
              key: const Key('settings-concurrent-downloads'),
              value: draft.concurrentDownloads.toDouble(),
              min: 1,
              max: AppSettings.maxConcurrentDownloads.toDouble(),
              onChanged: (v) =>
                  onChanged(draft.copyWith(concurrentDownloads: v.round())),
            ),
          ),
          Gaps.h16,
          EditableStringList(
            title: l10n.settingIgnoredDomains,
            info: l10n.settingIgnoredDomainsInfo,
            values: draft.ignoredDomains,
            addLabel: l10n.settingAddDomain,
            onChanged: (list) =>
                onChanged(draft.copyWith(ignoredDomains: list)),
          ),
        ],
      ),
    );
  }
}
