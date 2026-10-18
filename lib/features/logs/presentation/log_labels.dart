/// Localised names, icons and colours of the log levels and sources, plus
/// the lists the log toolbar offers as filters.
library;

import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/core/logging/log_entry.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Levels offered as filter chips; debug entries sit behind their own
/// toggle (debug builds only).
const List<LogLevel> logFilterLevels = [
  LogLevel.info,
  LogLevel.success,
  LogLevel.warning,
  LogLevel.error,
];

/// Sources offered in the source menu; the debug source is only ever used
/// by debug-level entries, which the debug toggle controls.
const List<LogSource> logFilterSources = [
  LogSource.app,
  LogSource.library,
  LogSource.download,
  LogSource.urlCheck,
  LogSource.workshop,
  LogSource.backup,
  LogSource.import,
  LogSource.cleanup,
  LogSource.settings,
];

/// Localised names and visuals of [LogLevel].
extension LogLevelLabels on LogLevel {
  /// Chip and filter label ("Warning"); `title` because [LogLevel.label]
  /// is the upper-case file-line tag.
  String title(AppLocalizations l10n) => switch (this) {
    LogLevel.info => l10n.logLevelInfo,
    LogLevel.success => l10n.logLevelSuccess,
    LogLevel.warning => l10n.logLevelWarning,
    LogLevel.error => l10n.logLevelError,
    LogLevel.debug => l10n.logLevelDebug,
  };

  /// Icon shown before the entry message.
  IconData get icon => switch (this) {
    LogLevel.info => Icons.info_outline,
    LogLevel.success => Icons.check_circle_outline,
    LogLevel.warning => Icons.warning_amber_rounded,
    LogLevel.error => Icons.error_outline,
    LogLevel.debug => Icons.bug_report_outlined,
  };

  /// Colour of the icon, from the theme's [VaultColors].
  Color color(BuildContext context) {
    final colors = VaultColors.of(context);
    return switch (this) {
      LogLevel.info => colors.logInfo,
      LogLevel.success => colors.logSuccess,
      LogLevel.warning => colors.logWarning,
      LogLevel.error => colors.logError,
      LogLevel.debug => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }
}

/// Localised names of [LogSource].
extension LogSourceLabels on LogSource {
  /// Chip and menu label ("URL check").
  String title(AppLocalizations l10n) => switch (this) {
    LogSource.app => l10n.logSourceApp,
    LogSource.library => l10n.logSourceLibrary,
    LogSource.download => l10n.logSourceDownload,
    LogSource.urlCheck => l10n.logSourceUrlCheck,
    LogSource.workshop => l10n.logSourceWorkshop,
    LogSource.backup => l10n.logSourceBackup,
    LogSource.import => l10n.logSourceImport,
    LogSource.cleanup => l10n.logSourceCleanup,
    LogSource.settings => l10n.logSourceSettings,
    LogSource.debug => l10n.logSourceDebug,
  };
}

/// `HH:mm:ss` of [time] (local), the short form the panel rows show.
String formatLogTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
