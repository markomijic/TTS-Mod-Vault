/// The Network section of the Settings dialog: download concurrency, the
/// check after downloads, the "Check all Mods and Saves domains" action and
/// the excluded domains.
library;

import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/data/net/domain_reachability_checker.dart'
    show DomainCheckResult;
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';
import 'package:tts_mod_vault/features/settings/application/check_domains_operation.dart';
import 'package:tts_mod_vault/features/settings/presentation/domain_reachability_dialog.dart';
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
          SettingsSwitchTile(
            key: const Key('settings-check-after-download'),
            title: l10n.settingCheckAfterDownload,
            info: l10n.settingCheckAfterDownloadInfo,
            value: draft.checkAfterDownload,
            onChanged: (v) => onChanged(draft.copyWith(checkAfterDownload: v)),
          ),
          Gaps.h16,
          const CheckDomainsButton(),
          Gaps.h8,
          Text(l10n.settingCheckDomainsInfo),
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

/// Runs the domain check of Mods and Saves and shows its results. While it
/// runs the button shows a spinner and a Cancel button sits next to it (the
/// progress bar's cancel is behind the modal Settings dialog).
class CheckDomainsButton extends HookConsumerWidget {
  /// Creates the button.
  const CheckDomainsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final checking = useState(false);
    final otherRunning =
        ref.watch(anyOperationRunningProvider) && !checking.value;

    Future<void> check() async {
      final ui = OperationUi.of(context);
      checking.value = true;
      final DomainCheckResult? result;
      try {
        result = await ui.launch(
          ref.read(domainCheckServiceProvider).checkAllModAndSaveDomains,
        );
      } finally {
        if (context.mounted) checking.value = false;
      }
      if (result == null || result.cancelled) return;
      final domains = result.domains;
      await ui.showAppDialog<void>(
        (_) => DomainReachabilityDialog(domains: domains),
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            key: const Key('settings-check-domains'),
            onPressed: checking.value || otherRunning ? null : check,
            icon: checking.value
                ? const SizedBox.square(
                    dimension: Insets.lg,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore),
            label: Text(
              checking.value
                  ? l10n.operationCheckingDomains
                  : l10n.settingCheckDomains,
            ),
          ),
        ),
        if (checking.value) ...[
          Gaps.w8,
          TextButton(
            onPressed: () =>
                ref.read(operationRunnerProvider.notifier).cancel(),
            child: Text(l10n.cancel),
          ),
        ],
      ],
    );
  }
}
