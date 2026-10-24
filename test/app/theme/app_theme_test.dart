import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_presets.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';

/// WCAG 2.x minimum contrast for body text.
const double minContrast = 4.5;

/// WCAG relative-luminance contrast ratio of two opaque colours (1..21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('contrast', () {
    for (final preset in ThemePresets.all) {
      for (final brightness in Brightness.values) {
        test('${preset.id} / ${brightness.name} semantic colours are readable '
            'on the surfaces', () {
          final theme = AppTheme.build(
            ThemeSettings.fromPreset(preset),
            brightness,
          );
          final scheme = theme.colorScheme;
          final colors = theme.extension<VaultColors>()!;
          final backgrounds = {
            'surface': scheme.surface,
            'surfaceContainer': scheme.surfaceContainer,
          };
          final foregrounds = {
            // Asset URL rows and tile placeholders.
            'assetPresent': colors.assetPresent,
            'assetMissing': colors.assetMissing,
            'assetInvalid': colors.assetInvalid,
            // Backup badges.
            'backupUpToDate': colors.backupUpToDate,
            'backupOutOfDate': colors.backupOutOfDate,
            'backupMismatch': colors.backupMismatch,
            'backupNone': colors.backupNone,
            // Log rows.
            'logInfo': colors.logInfo,
            'logSuccess': colors.logSuccess,
            'logWarning': colors.logWarning,
            'logError': colors.logError,
            // Selected-card border and destructive text.
            'primary (selected border)': scheme.primary,
            'error': scheme.error,
            'onSurface': scheme.onSurface,
            'onSurfaceVariant': scheme.onSurfaceVariant,
          };
          for (final MapEntry(key: name, value: color) in foregrounds.entries) {
            for (final MapEntry(key: bgName, value: background)
                in backgrounds.entries) {
              final ratio = contrastRatio(color, background);
              expect(
                ratio,
                greaterThanOrEqualTo(minContrast),
                reason:
                    '$name ${_hex(color)} on $bgName ${_hex(background)}: '
                    '${ratio.toStringAsFixed(2)}',
              );
            }
          }
        });
      }
    }

    test('contrastRatio is symmetric and spans 1..21', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      expect(contrastRatio(black, white), closeTo(21, 0.01));
      expect(contrastRatio(white, black), closeTo(21, 0.01));
      expect(contrastRatio(white, white), closeTo(1, 0.001));
    });
  });

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

    test('surfaces are neutral greys whatever the accent', () {
      for (final preset in ThemePresets.all) {
        for (final brightness in Brightness.values) {
          final scheme = AppTheme.build(
            ThemeSettings.fromPreset(preset),
            brightness,
          ).colorScheme;
          for (final surface in [
            scheme.surface,
            scheme.surfaceContainerLow,
            scheme.surfaceContainer,
            scheme.surfaceContainerHigh,
          ]) {
            expect(surface.r, closeTo(surface.b, 0.03), reason: preset.id);
            expect(surface.g, closeTo(surface.b, 0.03), reason: preset.id);
          }
        }
      }
    });

    test('the accent keeps the seed hue and reads as text', () {
      for (final brightness in Brightness.values) {
        final scheme = AppTheme.build(
          ThemeSettings.fromPreset(ThemePresets.yellow),
          brightness,
        ).colorScheme;
        expect(
          HSLColor.fromColor(scheme.primary).hue,
          closeTo(HSLColor.fromColor(const Color(0xFFFFCC00)).hue, 2),
        );
        expect(contrastRatio(scheme.primary, scheme.surface), greaterThan(4.4));
        expect(
          contrastRatio(scheme.onPrimary, scheme.primary),
          greaterThan(4.4),
        );
      }
    });

    test('body text follows the macOS scale', () {
      final theme = AppTheme.build(ThemeSettings.defaults(), Brightness.light);
      expect(theme.textTheme.bodyMedium?.fontSize, 13);
      expect(theme.textTheme.titleSmall?.fontWeight, FontWeight.w600);
      for (final style in [
        theme.textTheme.bodySmall,
        theme.textTheme.labelSmall,
      ]) {
        expect(style!.fontSize, greaterThanOrEqualTo(10));
      }
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
      expect(
        high.colorScheme.outlineVariant,
        isNot(standard.colorScheme.outlineVariant),
      );
      expect(
        contrastRatio(high.colorScheme.primary, high.colorScheme.surface),
        greaterThanOrEqualTo(
          contrastRatio(
            standard.colorScheme.primary,
            standard.colorScheme.surface,
          ),
        ),
      );
    });
  });

  group('VaultColors', () {
    test('fromScheme lifts every semantic colour to the minimum contrast', () {
      // System orange and green are too light on white as text;
      // fromScheme must correct them for any scheme.
      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFFF9A825),
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        );
        final colors = VaultColors.fromScheme(scheme);
        for (final color in [
          colors.assetPresent,
          colors.assetInvalid,
          colors.logInfo,
          colors.backupNone,
        ]) {
          expect(
            contrastRatio(color, scheme.surface),
            greaterThanOrEqualTo(minContrast),
          );
          expect(
            contrastRatio(color, scheme.surfaceContainer),
            greaterThanOrEqualTo(minContrast),
          );
        }
      }
    });

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

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
