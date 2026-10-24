import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// A named accent colour the user can pick from, after the macOS accent
/// colours.
///
/// Labels are resolved through [label] so they live in the ARB file.
@immutable
final class ThemePreset {
  /// Creates a preset.
  const ThemePreset({required this.id, required this.seed});

  /// Stable identifier stored in `ThemeSettings.presetId`.
  final String id;

  /// Accent colour as a 32-bit ARGB value.
  final int seed;

  /// Localised, user-facing name of this preset.
  String label(AppLocalizations l10n) => switch (id) {
    ThemePresets.blueId => l10n.themePresetBlue,
    ThemePresets.purpleId => l10n.themePresetPurple,
    ThemePresets.pinkId => l10n.themePresetPink,
    ThemePresets.redId => l10n.themePresetRed,
    ThemePresets.orangeId => l10n.themePresetOrange,
    ThemePresets.yellowId => l10n.themePresetYellow,
    ThemePresets.greenId => l10n.themePresetGreen,
    ThemePresets.graphiteId => l10n.themePresetGraphite,
    _ => id,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemePreset && other.id == id && other.seed == seed;

  @override
  int get hashCode => Object.hash(id, seed);

  @override
  String toString() => 'ThemePreset($id)';
}

/// The built-in accent colours.
abstract final class ThemePresets {
  /// Id of [blue].
  static const String blueId = 'blue';

  /// Id of [purple].
  static const String purpleId = 'purple';

  /// Id of [pink].
  static const String pinkId = 'pink';

  /// Id of [red].
  static const String redId = 'red';

  /// Id of [orange].
  static const String orangeId = 'orange';

  /// Id of [yellow].
  static const String yellowId = 'yellow';

  /// Id of [green].
  static const String greenId = 'green';

  /// Id of [graphite].
  static const String graphiteId = 'graphite';

  /// System blue; the application default.
  static const ThemePreset blue = ThemePreset(id: blueId, seed: 0xFF007AFF);

  /// System purple.
  static const ThemePreset purple = ThemePreset(id: purpleId, seed: 0xFFAF52DE);

  /// System pink.
  static const ThemePreset pink = ThemePreset(id: pinkId, seed: 0xFFFF2D55);

  /// System red.
  static const ThemePreset red = ThemePreset(id: redId, seed: 0xFFFF3B30);

  /// System orange.
  static const ThemePreset orange = ThemePreset(id: orangeId, seed: 0xFFFF9500);

  /// System yellow.
  static const ThemePreset yellow = ThemePreset(id: yellowId, seed: 0xFFFFCC00);

  /// System green.
  static const ThemePreset green = ThemePreset(id: greenId, seed: 0xFF34C759);

  /// Neutral grey, for an accent without colour.
  static const ThemePreset graphite = ThemePreset(
    id: graphiteId,
    seed: 0xFF8E8E93,
  );

  /// Every preset, in display order (the macOS order).
  static const List<ThemePreset> all = [
    blue,
    purple,
    pink,
    red,
    orange,
    yellow,
    green,
    graphite,
  ];

  /// The preset new installations start with.
  static const ThemePreset defaultPreset = blue;

  /// Presets of 3.0 pre-releases, which tinted the whole palette, mapped to
  /// the accent closest to them.
  static const Map<String, String> legacyIds = {
    'vault': purpleId,
    'classic': graphiteId,
    'ocean': blueId,
    'forest': greenId,
    'ember': orangeId,
    'rose': pinkId,
  };

  /// Looks a preset up by [id]; null when unknown.
  static ThemePreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
