import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Semantic colours that are not part of [ColorScheme]: asset and backup
/// status plus log levels.
///
/// Create one with [VaultColors.fromScheme] so the hues are harmonised with
/// the scheme's primary colour and have the right tone for its brightness.
/// Read it with [VaultColors.of].
@immutable
final class VaultColors extends ThemeExtension<VaultColors> {
  /// Creates the extension from explicit colours.
  const VaultColors({
    required this.assetPresent,
    required this.assetMissing,
    required this.assetInvalid,
    required this.backupUpToDate,
    required this.backupOutOfDate,
    required this.backupMismatch,
    required this.backupNone,
    required this.logInfo,
    required this.logSuccess,
    required this.logWarning,
    required this.logError,
  });

  /// Derives every colour from [scheme].
  ///
  /// Success, warning and info hues are seeded from fixed reference colours,
  /// nudged towards the scheme's primary hue (like Material's harmonisation)
  /// and then run through `ColorScheme.fromSeed` for [scheme]'s brightness so
  /// they land on the same tones as the scheme itself. Error states reuse
  /// [ColorScheme.error].
  factory VaultColors.fromScheme(ColorScheme scheme) {
    Color tone(int referenceSeed) => ColorScheme.fromSeed(
      seedColor: _harmonize(Color(referenceSeed), scheme.primary),
      brightness: scheme.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).primary;

    final success = tone(_successSeed);
    final warning = tone(_warningSeed);
    final info = tone(_infoSeed);
    final error = scheme.error;

    return VaultColors(
      assetPresent: success,
      assetMissing: error,
      assetInvalid: warning,
      backupUpToDate: success,
      backupOutOfDate: warning,
      backupMismatch: error,
      backupNone: scheme.onSurfaceVariant,
      logInfo: info,
      logSuccess: success,
      logWarning: warning,
      logError: error,
    );
  }

  static const int _successSeed = 0xFF2E7D32;
  static const int _warningSeed = 0xFFF9A825;
  static const int _infoSeed = 0xFF1565C0;

  /// Maximum hue rotation applied when harmonising, in degrees.
  static const double _maxHarmonizeDegrees = 15;

  /// Returns the [VaultColors] registered on the current theme.
  static VaultColors of(BuildContext context) =>
      Theme.of(context).extension<VaultColors>()!;

  /// Asset file exists on disk.
  final Color assetPresent;

  /// Asset file is missing.
  final Color assetMissing;

  /// Asset file exists but is not valid (wrong type, zero bytes, ...).
  final Color assetInvalid;

  /// Backup is newer than or equal to the mod.
  final Color backupUpToDate;

  /// Backup exists but the mod changed since.
  final Color backupOutOfDate;

  /// Backup exists but does not match the mod (different content).
  final Color backupMismatch;

  /// No backup exists.
  final Color backupNone;

  /// Informational log entry.
  final Color logInfo;

  /// Success log entry.
  final Color logSuccess;

  /// Warning log entry.
  final Color logWarning;

  /// Error log entry.
  final Color logError;

  @override
  VaultColors copyWith({
    Color? assetPresent,
    Color? assetMissing,
    Color? assetInvalid,
    Color? backupUpToDate,
    Color? backupOutOfDate,
    Color? backupMismatch,
    Color? backupNone,
    Color? logInfo,
    Color? logSuccess,
    Color? logWarning,
    Color? logError,
  }) => VaultColors(
    assetPresent: assetPresent ?? this.assetPresent,
    assetMissing: assetMissing ?? this.assetMissing,
    assetInvalid: assetInvalid ?? this.assetInvalid,
    backupUpToDate: backupUpToDate ?? this.backupUpToDate,
    backupOutOfDate: backupOutOfDate ?? this.backupOutOfDate,
    backupMismatch: backupMismatch ?? this.backupMismatch,
    backupNone: backupNone ?? this.backupNone,
    logInfo: logInfo ?? this.logInfo,
    logSuccess: logSuccess ?? this.logSuccess,
    logWarning: logWarning ?? this.logWarning,
    logError: logError ?? this.logError,
  );

  @override
  VaultColors lerp(ThemeExtension<VaultColors>? other, double t) {
    if (other is! VaultColors) return this;
    return VaultColors(
      assetPresent: Color.lerp(assetPresent, other.assetPresent, t)!,
      assetMissing: Color.lerp(assetMissing, other.assetMissing, t)!,
      assetInvalid: Color.lerp(assetInvalid, other.assetInvalid, t)!,
      backupUpToDate: Color.lerp(backupUpToDate, other.backupUpToDate, t)!,
      backupOutOfDate: Color.lerp(backupOutOfDate, other.backupOutOfDate, t)!,
      backupMismatch: Color.lerp(backupMismatch, other.backupMismatch, t)!,
      backupNone: Color.lerp(backupNone, other.backupNone, t)!,
      logInfo: Color.lerp(logInfo, other.logInfo, t)!,
      logSuccess: Color.lerp(logSuccess, other.logSuccess, t)!,
      logWarning: Color.lerp(logWarning, other.logWarning, t)!,
      logError: Color.lerp(logError, other.logError, t)!,
    );
  }

  /// Rotates [source]'s hue towards [target]'s by half their difference,
  /// capped at [_maxHarmonizeDegrees]. Achromatic targets (monochrome
  /// schemes) leave [source] untouched.
  static Color _harmonize(Color source, Color target) {
    final targetHsl = HSLColor.fromColor(target);
    if (targetHsl.saturation < 0.1) return source;
    final sourceHsl = HSLColor.fromColor(source);
    var delta = (targetHsl.hue - sourceHsl.hue) % 360;
    if (delta > 180) delta -= 360;
    final shift = delta.sign * math.min(delta.abs() / 2, _maxHarmonizeDegrees);
    return sourceHsl.withHue((sourceHsl.hue + shift) % 360).toColor();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultColors &&
          other.assetPresent == assetPresent &&
          other.assetMissing == assetMissing &&
          other.assetInvalid == assetInvalid &&
          other.backupUpToDate == backupUpToDate &&
          other.backupOutOfDate == backupOutOfDate &&
          other.backupMismatch == backupMismatch &&
          other.backupNone == backupNone &&
          other.logInfo == logInfo &&
          other.logSuccess == logSuccess &&
          other.logWarning == logWarning &&
          other.logError == logError;

  @override
  int get hashCode => Object.hash(
    assetPresent,
    assetMissing,
    assetInvalid,
    backupUpToDate,
    backupOutOfDate,
    backupMismatch,
    backupNone,
    logInfo,
    logSuccess,
    logWarning,
    logError,
  );
}
