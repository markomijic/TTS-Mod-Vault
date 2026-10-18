import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// A named seed colour + scheme variant the user can pick from.
///
/// Labels are resolved through [label] so they live in the ARB file.
@immutable
final class ThemePreset {
  /// Creates a preset.
  const ThemePreset({
    required this.id,
    required this.seed,
    required this.variant,
  });

  /// Stable identifier stored in `ThemeSettings.presetId`.
  final String id;

  /// Seed colour as a 32-bit ARGB value.
  final int seed;

  /// Scheme variant used with [seed].
  final DynamicSchemeVariant variant;

  /// Localised, user-facing name of this preset.
  String label(AppLocalizations l10n) => switch (id) {
    ThemePresets.vaultId => l10n.themePresetVault,
    ThemePresets.classicId => l10n.themePresetClassic,
    ThemePresets.oceanId => l10n.themePresetOcean,
    ThemePresets.forestId => l10n.themePresetForest,
    ThemePresets.emberId => l10n.themePresetEmber,
    ThemePresets.roseId => l10n.themePresetRose,
    _ => id,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemePreset &&
          other.id == id &&
          other.seed == seed &&
          other.variant == variant;

  @override
  int get hashCode => Object.hash(id, seed, variant);

  @override
  String toString() => 'ThemePreset($id)';
}

/// The built-in theme presets.
abstract final class ThemePresets {
  /// Id of [vault].
  static const String vaultId = 'vault';

  /// Id of [classic].
  static const String classicId = 'classic';

  /// Id of [ocean].
  static const String oceanId = 'ocean';

  /// Id of [forest].
  static const String forestId = 'forest';

  /// Id of [ember].
  static const String emberId = 'ember';

  /// Id of [rose].
  static const String roseId = 'rose';

  /// Material 3 baseline purple seed; the application default.
  static const ThemePreset vault = ThemePreset(
    id: vaultId,
    seed: 0xFF6750A4,
    variant: DynamicSchemeVariant.tonalSpot,
  );

  /// Approximates the 2.x look: near-black surfaces with white text and
  /// controls. The seed is the v2 scaffold colour; `monochrome` removes all
  /// chroma so the palette is pure greys.
  static const ThemePreset classic = ThemePreset(
    id: classicId,
    seed: 0xFF141218,
    variant: DynamicSchemeVariant.monochrome,
  );

  /// Blue seed palette.
  static const ThemePreset ocean = ThemePreset(
    id: oceanId,
    seed: 0xFF1565C0,
    variant: DynamicSchemeVariant.tonalSpot,
  );

  /// Green seed palette.
  static const ThemePreset forest = ThemePreset(
    id: forestId,
    seed: 0xFF2E7D32,
    variant: DynamicSchemeVariant.tonalSpot,
  );

  /// Orange seed palette with the seed's own chroma kept.
  static const ThemePreset ember = ThemePreset(
    id: emberId,
    seed: 0xFFE65100,
    variant: DynamicSchemeVariant.fidelity,
  );

  /// Pink seed palette.
  static const ThemePreset rose = ThemePreset(
    id: roseId,
    seed: 0xFFC2185B,
    variant: DynamicSchemeVariant.vibrant,
  );

  /// Every preset, in display order.
  static const List<ThemePreset> all = [
    vault,
    classic,
    ocean,
    forest,
    ember,
    rose,
  ];

  /// The preset new installations start with.
  static const ThemePreset defaultPreset = vault;

  /// Looks a preset up by [id]; null when unknown.
  static ThemePreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
