import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/theme_presets.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';

void main() {
  group('ThemeSettings', () {
    test('defaults use the default preset in dark mode', () {
      final settings = ThemeSettings.defaults();
      expect(settings.mode, ThemeMode.dark);
      expect(settings.presetId, ThemePresets.defaultPreset.id);
      expect(settings.seedColor, ThemePresets.defaultPreset.seed);
      expect(settings.variant, ThemePresets.defaultPreset.variant);
      expect(settings.contrast, 0);
    });

    test('round-trips through JSON', () {
      const original = ThemeSettings(
        mode: ThemeMode.light,
        seedColor: 0xFF1565C0,
        variant: DynamicSchemeVariant.vibrant,
        contrast: 0.5,
        presetId: 'ocean',
      );
      final encoded = jsonEncode(original.toJson());
      final decoded = ThemeSettings.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );
      expect(decoded, original);
      expect(decoded.hashCode, original.hashCode);
    });

    test('round-trips a null presetId', () {
      final original = ThemeSettings.defaults().copyWith(
        seedColor: 0xFF123456,
        clearPresetId: true,
      );
      final decoded = ThemeSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );
      expect(decoded.presetId, isNull);
      expect(decoded, original);
    });

    test('falls back to defaults for malformed fields', () {
      final defaults = ThemeSettings.defaults();
      final decoded = ThemeSettings.fromJson({
        'mode': 'sepia',
        'seedColor': 'blue',
        'variant': 42,
        'contrast': 'high',
        'presetId': 7,
      });
      expect(decoded.mode, defaults.mode);
      expect(decoded.seedColor, defaults.seedColor);
      expect(decoded.variant, defaults.variant);
      expect(decoded.contrast, defaults.contrast);
      expect(decoded.presetId, isNull);
    });

    test('clamps contrast to the supported range', () {
      expect(
        ThemeSettings.fromJson({'contrast': 5}).contrast,
        ThemeSettings.maxContrast,
      );
      expect(
        ThemeSettings.fromJson({'contrast': -5}).contrast,
        ThemeSettings.minContrast,
      );
    });

    test('copyWith replaces only the given fields', () {
      final base = ThemeSettings.defaults();
      final copy = base.copyWith(mode: ThemeMode.system);
      expect(copy.mode, ThemeMode.system);
      expect(copy.seedColor, base.seedColor);
      expect(copy.variant, base.variant);
      expect(copy.presetId, base.presetId);
      expect(copy, isNot(base));
    });
  });

  group('ThemePresets', () {
    test('ids are unique and resolvable', () {
      final ids = ThemePresets.all.map((p) => p.id).toSet();
      expect(ids.length, ThemePresets.all.length);
      for (final preset in ThemePresets.all) {
        expect(ThemePresets.byId(preset.id), preset);
      }
      expect(ThemePresets.byId('nope'), isNull);
    });

    test('classic preset is monochrome', () {
      expect(ThemePresets.classic.variant, DynamicSchemeVariant.monochrome);
    });
  });
}
