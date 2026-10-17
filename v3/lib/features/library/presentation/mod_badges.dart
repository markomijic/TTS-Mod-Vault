import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Date format used for file and backup dates on cards and rows.
final DateFormat modDateFormat = DateFormat.yMMMd().add_Hm();

/// Hover delay of the badge tooltips.
const Duration _tooltipWait = Duration(milliseconds: 300);

/// Backup status colour for [status].
Color backupStatusColor(VaultColors colors, BackupStatus status) =>
    switch (status) {
      BackupStatus.none => colors.backupNone,
      BackupStatus.upToDate => colors.backupUpToDate,
      BackupStatus.outOfDate => colors.backupOutOfDate,
      BackupStatus.assetCountMismatch => colors.backupMismatch,
    };

/// Tooltip of the backup badge: status, backup date, asset count and, on a
/// mismatch, the mod's own count.
String backupTooltip(AppLocalizations l10n, Mod mod) {
  final backup = mod.backup;
  final lines = [mod.backupStatus.label(l10n)];
  if (backup != null) {
    lines
      ..add(l10n.backupTooltipModified(modDateFormat.format(backup.modified)))
      ..add(l10n.backupTooltipAssets(backup.assetCount));
    if (mod.backupStatus == BackupStatus.assetCountMismatch) {
      lines.add(l10n.backupTooltipMismatch(mod.summary.present));
    }
  }
  return lines.join('\n');
}

/// The backup status icon with its tooltip. Renders nothing when [mod] has
/// no backup status or [visible] is false.
class BackupStatusBadge extends StatelessWidget {
  /// Creates the badge.
  const BackupStatusBadge({
    super.key,
    required this.mod,
    required this.visible,
    this.size = Insets.lg + Insets.xs,
  });

  /// The mod whose status is shown.
  final Mod mod;

  /// Whether the badge is shown at all (the "show backup state" option).
  final bool visible;

  /// Icon size.
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!visible || mod.backupStatus == BackupStatus.none) {
      return const SizedBox.shrink();
    }
    final colors = VaultColors.of(context);
    return Tooltip(
      waitDuration: _tooltipWait,
      message: backupTooltip(AppLocalizations.of(context), mod),
      child: Icon(
        Icons.folder_zip_outlined,
        size: size,
        color: backupStatusColor(colors, mod.backupStatus),
      ),
    );
  }
}

/// "N missing" in the asset-missing colour; nothing when all assets are on
/// disk.
class MissingCountBadge extends StatelessWidget {
  /// Creates the badge.
  const MissingCountBadge({super.key, required this.mod});

  /// The mod whose missing count is shown.
  final Mod mod;

  @override
  Widget build(BuildContext context) {
    final missing = mod.missingCount;
    if (missing <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Text(
      AppLocalizations.of(context).missingCount(missing),
      style: theme.textTheme.labelMedium?.copyWith(
        color: VaultColors.of(context).assetMissing,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Speaker icon shown when the mod references audio assets.
class AudioBadge extends StatelessWidget {
  /// Creates the badge.
  const AudioBadge({
    super.key,
    required this.mod,
    this.size = Insets.lg + Insets.xs,
  });

  /// The mod.
  final Mod mod;

  /// Icon size.
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!mod.summary.hasAudio) return const SizedBox.shrink();
    return Tooltip(
      waitDuration: _tooltipWait,
      message: AppLocalizations.of(context).hasAudioTooltip,
      child: Icon(
        Icons.audiotrack,
        size: size,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Translucent rounded backdrop for badges laid over a card image.
class BadgeBackdrop extends StatelessWidget {
  /// Creates the backdrop.
  const BadgeBackdrop({super.key, required this.child});

  /// The badge content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(Insets.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.xs,
          vertical: Insets.xs / 2,
        ),
        child: child,
      ),
    );
  }
}
