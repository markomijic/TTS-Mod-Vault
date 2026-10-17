import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_presets.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';

void main() {
  group('AppTheme.build', () {
    for (final preset in ThemePresets.all) {
      for (final brightness in Brightness.values) {
        test('${preset.id} / ${brightness.name} has VaultColors', () {
          final theme = AppTheme.build(
            ThemeSettings.fromPreset(preset),
            brightness,
          );
          expect(theme.brightness, brightness);
          expect(theme.colorScheme.brightness, brightness);
          expect(theme.useMaterial3, isTrue);
          final colors = theme.extension<VaultColors>();
          expect(colors, isNotNull);
          expect(colors!.assetMissing, theme.colorScheme.error);
          expect(colors.backupMismatch, theme.colorScheme.error);
          expect(colors.assetPresent, isNot(colors.assetMissing));
          expect(colors.assetPresent, isNot(colors.assetInvalid));
          expect(colors.assetInvalid, isNot(colors.assetMissing));
        });
      }
    }

    test('classic dark theme is near black', () {
      final theme = AppTheme.build(
        ThemeSettings.fromPreset(ThemePresets.classic),
        Brightness.dark,
      );
      final surface = theme.colorScheme.surface;
      expect(surface.computeLuminance(), lessThan(0.02));
      // Monochrome: no chroma on the surface.
      expect(surface.r, closeTo(surface.g, 0.02));
      expect(surface.g, closeTo(surface.b, 0.02));
      expect(theme.colorScheme.onSurface.computeLuminance(), greaterThan(0.7));
    });

    test('buttons use the hand cursor when enabled', () {
      final theme = AppTheme.build(ThemeSettings.defaults(), Brightness.dark);
      final cursor = theme.iconButtonTheme.style?.mouseCursor;
      expect(cursor, isNotNull);
      expect(cursor!.resolve({}), SystemMouseCursors.click);
      expect(
        cursor.resolve({WidgetState.disabled}),
        isNot(SystemMouseCursors.click),
      );
      expect(
        theme.filledButtonTheme.style?.mouseCursor?.resolve({}),
        SystemMouseCursors.click,
      );
      expect(
        theme.textButtonTheme.style?.mouseCursor?.resolve({}),
        SystemMouseCursors.click,
      );
    });

    test('contrast level changes the scheme', () {
      final standard = AppTheme.build(
        ThemeSettings.defaults(),
        Brightness.dark,
      );
      final high = AppTheme.build(
        ThemeSettings.defaults().copyWith(contrast: 1),
        Brightness.dark,
      );
      expect(high.colorScheme.primary, isNot(standard.colorScheme.primary));
    });
  });

  group('VaultColors', () {
    test('lerp at the ends returns the inputs', () {
      final a = VaultColors.fromScheme(
        ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      );
      final b = VaultColors.fromScheme(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
      );
      expect(a.lerp(b, 0), a);
      expect(a.lerp(b, 1), b);
      expect(a.lerp(null, 0.5), a);
    });

    test('copyWith replaces a single colour', () {
      final a = VaultColors.fromScheme(
        ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      );
      final b = a.copyWith(logError: const Color(0xFF000001));
      expect(b.logError, const Color(0xFF000001));
      expect(b.logInfo, a.logInfo);
    });
  });
}
