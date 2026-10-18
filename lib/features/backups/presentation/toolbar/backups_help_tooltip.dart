import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// How long the help stays open once shown.
const Duration _showDuration = Duration(seconds: 15);

/// Info icon with the bullet help of the Backups tab, naming the platform's
/// multi-select modifier (Cmd on macOS, Ctrl elsewhere).
class BackupsHelpTooltip extends StatelessWidget {
  /// Creates the icon.
  const BackupsHelpTooltip({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isMac = theme.platform == TargetPlatform.macOS;
    final message = l10n.backupsHelp(
      isMac ? l10n.modifierCmd : l10n.modifierCtrl,
    );
    return Tooltip(
      message: message,
      showDuration: _showDuration,
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onInverseSurface,
        height: 1.6,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Insets.sm),
        child: Icon(
          Icons.info_outline,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
