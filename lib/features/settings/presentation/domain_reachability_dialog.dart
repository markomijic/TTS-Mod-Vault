/// The "Domain reachability results" dialog of the Settings domain check.
/// Port of 2.x `_DomainReachabilityResultsDialog`.
library;

import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/data/net/domain_reachability_checker.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

const double _dialogWidth = 560;
const double _dialogHeight = 420;

/// Lists every checked domain, unreachable ones first, under a summary
/// line.
class DomainReachabilityDialog extends StatelessWidget {
  /// Creates the dialog for [domains].
  const DomainReachabilityDialog({super.key, required this.domains});

  /// The checked domains, in any order.
  final List<DomainReachability> domains;

  /// [domains] unreachable first, then by name.
  static List<DomainReachability> sorted(List<DomainReachability> domains) =>
      [...domains]..sort((a, b) {
        if (a.reachable != b.reachable) return a.reachable ? 1 : -1;
        return a.domain.compareTo(b.domain);
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final vault = VaultColors.of(context);
    final reachable = domains.where((d) => d.reachable).length;
    final rows = sorted(domains);
    return AppDialog(
      title: l10n.domainResultsTitle,
      content: SizedBox(
        width: _dialogWidth,
        height: _dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              domains.isEmpty
                  ? l10n.domainResultsNone
                  : l10n.domainResultsSummary(
                      reachable,
                      domains.length - reachable,
                      domains.length,
                    ),
            ),
            Gaps.h12,
            if (rows.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      key: ValueKey('domain-result-${row.domain}'),
                      dense: true,
                      leading: Icon(
                        row.reachable ? Icons.check_circle : Icons.cancel,
                        color: row.reachable
                            ? vault.assetPresent
                            : scheme.error,
                      ),
                      title: SelectableText(row.domain),
                      trailing: Text(
                        row.reachable
                            ? l10n.domainReachable
                            : l10n.domainUnreachable,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
