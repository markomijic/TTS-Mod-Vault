import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/theme_presets.dart';

/// User-selected theme configuration.
///
/// Persisted as JSON through the key-value store (see `ThemeController`) and
/// turned into a [ThemeData] by `AppTheme.build`.
@immutable
final class ThemeSettings {
  /// Creates settings from explicit values.
  const ThemeSettings({
    required this.mode,
    required this.seedColor,
    required this.variant,
    required this.contrast,
    this.presetId,
  });

  /// The application default: the default preset in dark mode.
  factory ThemeSettings.defaults() => ThemeSettings.fromPreset(
    ThemePresets.defaultPreset,
    mode: ThemeMode.dark,
  );

  /// Settings that reproduce [preset] with the given [mode] and [contrast].
  factory ThemeSettings.fromPreset(
    ThemePreset preset, {
    ThemeMode mode = ThemeMode.system,
    double contrast = 0,
  }) => ThemeSettings(
    mode: mode,
    seedColor: preset.seed,
    variant: preset.variant,
    contrast: contrast,
    presetId: preset.id,
  );

  /// Restores settings from [json]; any missing or malformed field falls back
  /// to its default value so a corrupt record never prevents start-up.
  factory ThemeSettings.fromJson(Map<String, Object?> json) {
    final defaults = ThemeSettings.defaults();
    final mode = json['mode'];
    final seed = json['seedColor'];
    final variant = json['variant'];
    final contrast = json['contrast'];
    final presetId = json['presetId'];
    return ThemeSettings(
      mode: mode is String
          ? ThemeMode.values.asNameMap()[mode] ?? defaults.mode
          : defaults.mode,
      seedColor: seed is int ? seed : defaults.seedColor,
      variant: variant is String
          ? DynamicSchemeVariant.values.asNameMap()[variant] ?? defaults.variant
          : defaults.variant,
      contrast: contrast is num
          ? contrast.toDouble().clamp(minContrast, maxContrast)
          : defaults.contrast,
      presetId: presetId is String ? presetId : null,
    );
  }

  /// Lowest value accepted for [contrast] (Material's reduced contrast).
  static const double minContrast = -1;

  /// Highest value accepted for [contrast] (Material's maximum contrast).
  static const double maxContrast = 1;

  /// Light, dark or follow the operating system.
  final ThemeMode mode;

  /// Seed colour as a 32-bit ARGB value.
  final int seedColor;

  /// How the palette is derived from [seedColor].
  final DynamicSchemeVariant variant;

  /// Contrast level passed to `ColorScheme.fromSeed`, in
  /// [minContrast]..[maxContrast].
  final double contrast;

  /// Id of the preset [seedColor] and [variant] were taken from, or null when
  /// the user picked a custom seed colour.
  final String? presetId;

  /// Returns a copy with the given fields replaced.
  ///
  /// Pass `clearPresetId: true` to drop [presetId] (for example after the
  /// user picks a custom seed colour).
  ThemeSettings copyWith({
    ThemeMode? mode,
    int? seedColor,
    DynamicSchemeVariant? variant,
    double? contrast,
    String? presetId,
    bool clearPresetId = false,
  }) => ThemeSettings(
    mode: mode ?? this.mode,
    seedColor: seedColor ?? this.seedColor,
    variant: variant ?? this.variant,
    contrast: contrast ?? this.contrast,
    presetId: clearPresetId ? null : presetId ?? this.presetId,
  );

  /// Serialises to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'seedColor': seedColor,
    'variant': variant.name,
    'contrast': contrast,
    'presetId': presetId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeSettings &&
          other.mode == mode &&
          other.seedColor == seedColor &&
          other.variant == variant &&
          other.contrast == contrast &&
          other.presetId == presetId;

  @override
  int get hashCode => Object.hash(mode, seedColor, variant, contrast, presetId);

  @override
  String toString() =>
      'ThemeSettings(mode: $mode, seedColor: '
      '0x${seedColor.toRadixString(16).toUpperCase()}, variant: $variant, '
      'contrast: $contrast, presetId: $presetId)';
}
