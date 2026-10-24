import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// How long the help stays open once shown.
const Duration _showDuration = Duration(seconds: 15);

/// Info icon with the help of the selected-mod panel (2.x `HelpTooltip`):
/// a colour legend for the URL rows, drawn in the theme's [VaultColors] so
/// it stays correct for every palette, followed by the list of actions.
class AssetHelpTooltip extends StatelessWidget {
  /// Creates the icon.
  const AssetHelpTooltip({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = VaultColors.of(context);
    final base = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurface,
      height: 1.6,
    );
    final bold = base?.copyWith(fontWeight: FontWeight.bold);

    TextSpan legend(Color color, String label) => TextSpan(
      children: [
        TextSpan(
          text: '● ',
          style: base?.copyWith(color: color),
        ),
        TextSpan(text: '$label\n'),
      ],
    );

    return Tooltip(
      showDuration: _showDuration,
      richMessage: TextSpan(
        style: base,
        children: [
          TextSpan(text: '${l10n.assetHelpStatusHeading}\n', style: bold),
          legend(colors.assetMissing, l10n.assetHelpMissing),
          legend(colors.assetPresent, l10n.assetHelpDownloaded),
          legend(colors.assetInvalid, l10n.assetHelpInvalid),
          legend(scheme.primary, l10n.assetHelpSelected),
          const TextSpan(text: '\n'),
          TextSpan(text: l10n.assetHelpActions),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Insets.sm),
        child: Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
