import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/backups/presentation/backup_labels.dart';
import 'package:tts_mod_vault/features/library/presentation/mod_badges.dart'
    show formatModDate;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Hover delay of the badge tooltip.
const Duration _tooltipWait = Duration(milliseconds: 300);

/// Colour of the matched/unmatched badge: `backupUpToDate` when a mod in
/// the library produces the backup's name, `backupNone` otherwise.
Color backupMatchColor(VaultColors colors, Backup backup) =>
    backup.hasMatchingMod ? colors.backupUpToDate : colors.backupNone;

/// Tooltip of the match badge: match state, size, asset count and date.
String backupBadgeTooltip(AppLocalizations l10n, Backup backup) => [
  backup.matchLabel(l10n),
  backup.fileSizeLabel,
  l10n.backupTooltipAssets(backup.assetCount),
  formatModDate(l10n.localeName, backup.modified),
].join('\n');

/// The matched/unmatched icon with its tooltip.
class BackupMatchBadge extends StatelessWidget {
  /// Creates the badge.
  const BackupMatchBadge({
    super.key,
    required this.backup,
    this.size = Insets.lg + Insets.xs,
  });

  /// The backup whose state is shown.
  final Backup backup;

  /// Icon size.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = VaultColors.of(context);
    return Tooltip(
      waitDuration: _tooltipWait,
      message: backupBadgeTooltip(AppLocalizations.of(context), backup),
      child: Icon(
        backup.hasMatchingMod ? Icons.extension : Icons.extension_off_outlined,
        size: size,
        color: backupMatchColor(colors, backup),
      ),
    );
  }
}
