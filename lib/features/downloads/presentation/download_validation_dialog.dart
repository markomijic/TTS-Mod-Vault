import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart'
    show DownloadValidationResult;
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 900;

/// Shows a [DownloadValidationDialog] for the [results] that have
/// something to report; shows nothing when none has.
Future<void> showDownloadValidationResults(
  OperationUi ui,
  Iterable<DownloadValidationResult> results,
) async {
  final withIssues = [
    for (final result in results)
      if (result.hasIssues) result,
  ];
  if (withIssues.isEmpty || !ui.mounted) return;
  await ui.showAppDialog<void>(
    (_) => DownloadValidationDialog(results: withIssues),
  );
}

/// Port of the 2.x "Download check results" dialog (`051741c`): after a
/// download, the hosts of still-missing files that could not be reached
/// (orange; their files were not marked invalid) and the dead URLs on
/// reachable hosts (red), each grouped per mod, everything selectable.
class DownloadValidationDialog extends StatelessWidget {
  /// Creates the dialog for [results] (each with [DownloadValidationResult.hasIssues]).
  const DownloadValidationDialog({super.key, required this.results});

  /// The per-mod checks shown.
  final List<DownloadValidationResult> results;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = VaultColors.of(context);
    final unreachable = [
      for (final r in results)
        if (r.unreachableDomains.isNotEmpty)
          (r.mod.displayName, r.unreachableDomains),
    ];
    final invalid = [
      for (final r in results)
        if (r.invalidUrls.isNotEmpty) (r.mod.displayName, r.invalidUrls),
    ];
    final allInvalid = [for (final (_, urls) in invalid) ...urls];

    return AppDialog(
      title: l10n.downloadValidationTitle,
      content: SizedBox(
        width: _dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unreachable.isNotEmpty)
                _Section(
                  icon: Icons.cloud_off,
                  color: colors.logWarning,
                  heading: l10n.downloadValidationUnreachableHeading,
                  note: l10n.downloadValidationUnreachableNote,
                  groups: unreachable,
                ),
              if (unreachable.isNotEmpty && invalid.isNotEmpty) Gaps.h16,
              if (invalid.isNotEmpty)
                _Section(
                  icon: Icons.error_outline,
                  color: colors.assetMissing,
                  heading: l10n.downloadValidationInvalidHeading,
                  note: l10n.downloadValidationInvalidNote,
                  groups: invalid,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        if (allInvalid.isNotEmpty)
          FilledButton.tonalIcon(
            onPressed: () =>
                copyTextToClipboard(context, allInvalid.join('\n')),
            icon: const Icon(Icons.copy_all),
            label: Text(l10n.urlCheckCopyAll),
          ),
      ],
    );
  }
}

/// A coloured heading with its note, then one block per mod: the mod's name
/// and its entries.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.color,
    required this.heading,
    required this.note,
    required this.groups,
  });

  final IconData icon;
  final Color color;
  final String heading;
  final String note;
  final List<(String, List<String>)> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            Gaps.w8,
            Text(
              heading,
              style: theme.textTheme.titleMedium?.copyWith(color: color),
            ),
          ],
        ),
        Gaps.h4,
        Text(
          note,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final (name, entries) in groups) ...[
          Gaps.h12,
          Text(
            name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Gaps.h4,
          Padding(
            padding: const EdgeInsets.only(left: Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final entry in entries) SelectableText(entry)],
            ),
          ),
        ],
      ],
    );
  }
}
