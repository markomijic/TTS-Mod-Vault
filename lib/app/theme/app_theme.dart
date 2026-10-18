import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';

/// Builds the application [ThemeData] from [ThemeSettings].
///
/// Every widget reads colours and text styles from the resulting theme (or
/// the [VaultColors] extension), so user theming never touches widgets.
abstract final class AppTheme {
  /// Corner radius shared by menus and dialogs.
  static const double menuRadius = 8;

  /// Builds the theme for [settings] at [brightness].
  static ThemeData build(ThemeSettings settings, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(settings.seedColor),
      brightness: brightness,
      dynamicSchemeVariant: settings.variant,
      contrastLevel: settings.contrast,
    );

    final base = ThemeData(
      colorScheme: scheme,
      visualDensity: VisualDensity.comfortable,
      extensions: [VaultColors.fromScheme(scheme)],
    );
    final textTheme = base.textTheme;

    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(menuRadius),
      side: BorderSide(color: scheme.outlineVariant),
    );

    return base.copyWith(
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom().copyWith(mouseCursor: _clickCursor),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom().copyWith(mouseCursor: _clickCursor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom().copyWith(mouseCursor: _clickCursor),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom().copyWith(mouseCursor: _clickCursor),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom().copyWith(mouseCursor: _clickCursor),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.sm,
          vertical: Insets.xs,
        ),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(Insets.xs),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          shape: WidgetStatePropertyAll(menuShape),
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: menuShape,
        color: scheme.surfaceContainer,
        textStyle: textTheme.bodyMedium,
        iconColor: scheme.onSurfaceVariant,
        mouseCursor: _clickCursor,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Insets.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 480,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(menuRadius),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: Insets.sm,
        thickness: 1,
        color: scheme.outlineVariant,
      ),
    );
  }

  /// Hand cursor on enabled buttons (as in 2.x), default arrow when disabled.
  static final WidgetStateProperty<MouseCursor> _clickCursor =
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
      );
}
