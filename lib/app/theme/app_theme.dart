import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/apple_palette.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';

/// Builds the application [ThemeData] from [ThemeSettings].
///
/// The look follows Apple's Human Interface Guidelines for desktop apps:
/// neutral grey surfaces ([ApplePalette]) with the user's colour as the
/// only accent, the macOS type scale one step up (14 pt body), compact 28 px controls,
/// hover highlights instead of ink ripples, and rounded sheets and menus on
/// the floating layer.
///
/// Every widget reads colours and text styles from the resulting theme (or
/// the [VaultColors] extension), so user theming never touches widgets.
abstract final class AppTheme {
  /// Corner radius of buttons, fields and other controls.
  static const double controlRadius = 6;

  /// Corner radius shared by menus, cards and list rows.
  static const double menuRadius = 8;

  /// Corner radius of grid cards (mod, backup and image thumbnails).
  static const double cardRadius = 6;

  /// Corner radius of dialogs (sheets).
  static const double dialogRadius = 14;

  /// Height of a regular push button or text field.
  static const double controlHeight = 28;

  /// Default icon size in toolbars, buttons and the sidebar.
  static const double iconSize = 18;

  /// Builds the theme for [settings] at [brightness].
  static ThemeData build(ThemeSettings settings, Brightness brightness) {
    final palette = ApplePalette.of(brightness);
    final scheme = colorScheme(settings, brightness);
    final textTheme = _textTheme(brightness, scheme);
    final overlay = _Overlays(scheme.onSurface);

    final base = ThemeData(
      colorScheme: scheme,
      textTheme: textTheme,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashFactory: NoSplash.splashFactory,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      hoverColor: overlay.hover,
      highlightColor: overlay.pressed,
      focusColor: overlay.hover,
      splashColor: Colors.transparent,
      extensions: [
        VaultColors.fromScheme(scheme, minimum: _textContrast(settings)),
      ],
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    // Menus and popovers float over content of the same grey in dark mode,
    // so they get the stronger control border there.
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(menuRadius),
      side: BorderSide(
        color: brightness == Brightness.dark
            ? scheme.outline
            : scheme.outlineVariant,
      ),
    );
    final focusRing = BorderSide(
      color: scheme.primary.withValues(alpha: 0.6),
      width: 3,
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: Insets.md);
    const buttonMinimumSize = Size(0, controlHeight);
    final buttonText = textTheme.labelLarge;

    // A hover or press overlay on top of a button's own fill.
    WidgetStateProperty<Color?> overlayOn(Color foreground) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return foreground.withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.hovered)) {
            return foreground.withValues(alpha: 0.08);
          }
          return null;
        });
    // A focus ring drawn as the button's border.
    WidgetStateProperty<BorderSide?> ringOr(BorderSide idle) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? focusRing : idle,
        );

    // Secondary push button: a neutral grey fill, like a macOS bordered
    // button.
    final pushButton = ButtonStyle(
      mouseCursor: _clickCursor,
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? palette.control.withValues(alpha: 0.5)
            : palette.control,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.38)
            : scheme.onSurface,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.38)
            : scheme.onSurface,
      ),
      overlayColor: overlayOn(scheme.onSurface),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      side: ringOr(BorderSide.none),
      shape: WidgetStatePropertyAll(controlShape),
      padding: const WidgetStatePropertyAll(buttonPadding),
      minimumSize: const WidgetStatePropertyAll(buttonMinimumSize),
      iconSize: const WidgetStatePropertyAll(16),
      textStyle: WidgetStatePropertyAll(buttonText),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return base.copyWith(
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _clickCursor,
          iconSize: const WidgetStatePropertyAll(iconSize),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return scheme.onSurfaceVariant;
          }),
          overlayColor: overlayOn(scheme.onSurface),
          side: ringOr(BorderSide.none),
          shape: WidgetStatePropertyAll(controlShape),
          minimumSize: const WidgetStatePropertyAll(Size.square(controlHeight)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(Insets.xs + 1)),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      // Primary push button: the accent fill (Apple's prominent style).
      // Colours are left to the defaults so `FilledButton.tonal` keeps its
      // own: secondaryContainer, which this scheme makes the grey of a
      // secondary push button.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _clickCursor,
          elevation: const WidgetStatePropertyAll(0),
          side: ringOr(BorderSide.none),
          shape: WidgetStatePropertyAll(controlShape),
          padding: const WidgetStatePropertyAll(buttonPadding),
          minimumSize: const WidgetStatePropertyAll(buttonMinimumSize),
          iconSize: const WidgetStatePropertyAll(16),
          textStyle: WidgetStatePropertyAll(buttonText),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: pushButton),
      outlinedButtonTheme: OutlinedButtonThemeData(style: pushButton),
      // Plain (borderless) button in the accent colour.
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _clickCursor,
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : null,
          ),
          overlayColor: overlayOn(scheme.onSurface),
          side: ringOr(BorderSide.none),
          shape: WidgetStatePropertyAll(controlShape),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Insets.sm),
          ),
          minimumSize: const WidgetStatePropertyAll(buttonMinimumSize),
          iconSize: const WidgetStatePropertyAll(16),
          textStyle: WidgetStatePropertyAll(buttonText),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      // Segmented control: a grey track with the selected segment raised.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _clickCursor,
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? palette.selected
                : palette.control,
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            return states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant;
          }),
          overlayColor: overlayOn(scheme.onSurface),
          side: WidgetStatePropertyAll(
            BorderSide(color: palette.control, width: 2),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Insets.md),
          ),
          minimumSize: const WidgetStatePropertyAll(buttonMinimumSize),
          iconSize: const WidgetStatePropertyAll(16),
          textStyle: WidgetStatePropertyAll(buttonText),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        selectedIcon: const SizedBox.shrink(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.control,
        selectedColor: scheme.primaryContainer,
        disabledColor: palette.control.withValues(alpha: 0.5),
        checkmarkColor: scheme.onPrimaryContainer,
        labelStyle: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 16),
        showCheckmark: true,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: true,
        fillColor: palette.control,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm + 2,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        // Floating labels render at 75 %, so 14 pt stays above the 10 pt
        // desktop minimum.
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: _inputBorder(BorderSide.none),
        enabledBorder: _inputBorder(BorderSide.none),
        disabledBorder: _inputBorder(BorderSide.none),
        focusedBorder: _inputBorder(focusRing),
        errorBorder: _inputBorder(BorderSide(color: scheme.error)),
        focusedErrorBorder: _inputBorder(
          BorderSide(color: scheme.error, width: 2),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.3),
        selectionHandleColor: scheme.primary,
      ),
      checkboxTheme: CheckboxThemeData(
        mouseCursor: _clickCursor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BorderSide.none
              : BorderSide(color: palette.border, width: 1.5),
        ),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (states.contains(WidgetState.disabled)
                    ? scheme.onSurface.withValues(alpha: 0.38)
                    : scheme.primary)
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      radioTheme: RadioThemeData(
        mouseCursor: _clickCursor,
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : palette.border,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      // Apple switch: a white knob on an accent or grey track.
      switchTheme: SwitchThemeData(
        mouseCursor: _clickCursor,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return palette.selected.withValues(alpha: 0.6);
          }
          // On a white (monochrome) track the knob takes the dark label.
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : const Color(0xFFFFFFFF);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          final color = on ? scheme.primary : palette.controlStrong;
          return states.contains(WidgetState.disabled)
              ? color.withValues(alpha: 0.5)
              : color;
        }),
        // An outlined off track keeps on and off apart when the accent is
        // a grey (Graphite).
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : palette.border,
        ),
        thumbIcon: const WidgetStatePropertyAll(null),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: palette.controlStrong,
        thumbColor: scheme.primary,
        overlayColor: Colors.transparent,
        mouseCursor: _clickCursor,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: palette.control,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
        borderRadius: BorderRadius.circular(2),
        strokeWidth: 3,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        selectedColor: scheme.onPrimaryContainer,
        selectedTileColor: scheme.primaryContainer,
        titleTextStyle: textTheme.bodyMedium,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        minVerticalPadding: Insets.xs,
        horizontalTitleGap: Insets.md,
        contentPadding: const EdgeInsets.symmetric(horizontal: Insets.md),
        mouseCursor: _clickCursor,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: scheme.onSurfaceVariant,
        collapsedIconColor: scheme.onSurfaceVariant,
        tilePadding: const EdgeInsets.symmetric(horizontal: Insets.sm),
      ),
      tabBarTheme: TabBarThemeData(
        indicator: BoxDecoration(
          color: palette.selected,
          borderRadius: BorderRadius.circular(controlRadius),
          border: Border.all(color: scheme.outlineVariant),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        overlayColor: overlayOn(scheme.onSurface),
        splashFactory: NoSplash.splashFactory,
        mouseCursor: _clickCursor,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.sm,
          vertical: Insets.xs,
        ),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(controlRadius),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: _shadow(brightness, blur: 8, offset: 2),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          shape: WidgetStatePropertyAll(menuShape),
          backgroundColor: WidgetStatePropertyAll(palette.raised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3),
          shadowColor: WidgetStatePropertyAll(_shadowColor(brightness)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(Insets.xs + 1)),
        ),
      ),
      // Menu items highlight in the accent colour, as on macOS.
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _clickCursor,
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? scheme.primary
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            return states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? scheme.onPrimary
                : scheme.onSurface;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            return states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Insets.sm + 2),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 26)),
          iconSize: const WidgetStatePropertyAll(16),
          textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
          visualDensity: VisualDensity.standard,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: menuShape,
        color: palette.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: _shadowColor(brightness),
        textStyle: textTheme.bodyMedium,
        iconColor: scheme.onSurfaceVariant,
        mouseCursor: _clickCursor,
        menuPadding: const EdgeInsets.all(Insets.xs + 1),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll(menuShape),
          backgroundColor: WidgetStatePropertyAll(palette.raised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      // Dialogs are sheets on the floating layer.
      dialogTheme: DialogThemeData(
        backgroundColor: palette.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(
          alpha: brightness == Brightness.light ? 0.2 : 0.35,
        ),
        barrierColor: Colors.black.withValues(
          alpha: brightness == Brightness.light ? 0.2 : 0.45,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        actionsPadding: const EdgeInsets.fromLTRB(
          Insets.xl,
          0,
          Insets.xl,
          Insets.lg,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.raised,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 480,
        elevation: 6,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(menuRadius + 2),
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: scheme.onError,
        textStyle: textTheme.labelSmall,
      ),
      dividerTheme: DividerThemeData(
        space: Insets.sm,
        thickness: 1,
        color: scheme.outlineVariant,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => scheme.onSurface.withValues(
            alpha:
                states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.dragged)
                ? 0.45
                : 0.28,
          ),
        ),
        crossAxisMargin: 2,
      ),
    );
  }

  /// The colour scheme for [settings] at [brightness]: Apple's neutral
  /// surfaces and labels, the user's colour as the accent (made readable on
  /// the surfaces), and system red for errors.
  static ColorScheme colorScheme(
    ThemeSettings settings,
    Brightness brightness,
  ) {
    final palette = ApplePalette.of(brightness);
    final textContrast = _textContrast(settings);
    // Positive contrast strengthens separators and secondary text; negative
    // softens separators only, so text never drops below its minimum.
    final level = settings.contrast;
    final light = brightness == Brightness.light;

    final surface = palette.content;
    final surfaces = [surface, palette.sidebar, palette.raised];
    Color readable(Color color) =>
        palette.readable(color, surfaces, minimum: textContrast);

    // A grey accent (Graphite or any grey hex) becomes the label colour:
    // white on dark, near-black on light. That is the monochrome look of
    // 2.x, with the accent still reserved for primary actions and
    // selection.
    final seed = Color(settings.seedColor);
    final accent = isMonochrome(seed) ? palette.label : readable(seed);
    final error = readable(palette.red);
    final secondaryLabel = palette.readable(palette.secondaryLabel, [
      ...surfaces,
      palette.control,
    ], minimum: textContrast);
    final separator = level == 0
        ? palette.separator
        : Color.lerp(
            palette.separator,
            level > 0 ? palette.border : surface,
            level.abs() * (level > 0 ? 1 : 0.5),
          )!;
    final border = level > 0
        ? Color.lerp(palette.border, palette.label, level * 0.4)!
        : palette.border;
    final primaryContainer = ApplePalette.tint(
      accent,
      surface,
      light ? 0.14 : 0.24,
    );
    final errorContainer = ApplePalette.tint(error, surface, light ? 0.1 : 0.2);

    return ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: palette.onFill(accent),
      primaryContainer: primaryContainer,
      onPrimaryContainer: palette.readable(accent, [
        primaryContainer,
      ], minimum: textContrast),
      inversePrimary: palette.readable(Color(settings.seedColor), [
        light ? ApplePalette.dark.raised : ApplePalette.light.raised,
      ]),
      secondary: accent,
      onSecondary: palette.onFill(accent),
      secondaryContainer: palette.control,
      onSecondaryContainer: palette.label,
      tertiary: accent,
      onTertiary: palette.onFill(accent),
      tertiaryContainer: primaryContainer,
      onTertiaryContainer: palette.label,
      error: error,
      onError: palette.onFill(error),
      errorContainer: errorContainer,
      onErrorContainer: palette.readable(error, [
        errorContainer,
      ], minimum: textContrast),
      surface: surface,
      onSurface: palette.label,
      onSurfaceVariant: secondaryLabel,
      surfaceDim: palette.contentLowest,
      surfaceBright: palette.raised,
      surfaceContainerLowest: palette.contentLowest,
      surfaceContainerLow: palette.sidebar,
      surfaceContainer: palette.raised,
      surfaceContainerHigh: palette.control,
      surfaceContainerHighest: palette.controlStrong,
      outline: border,
      outlineVariant: separator,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: light ? ApplePalette.dark.raised : palette.label,
      onInverseSurface: light ? ApplePalette.dark.label : palette.content,
      surfaceTint: Colors.transparent,
    );
  }

  /// Whether [color] has too little saturation to read as a hue (Graphite,
  /// greys, black and white).
  static bool isMonochrome(Color color) =>
      HSLColor.fromColor(color).saturation < 0.12;

  /// Minimum contrast for text and accents under [settings].
  static double _textContrast(ThemeSettings settings) =>
      ApplePalette.textContrast +
      (settings.contrast > 0 ? settings.contrast * 2.5 : 0);

  /// The macOS text styles mapped onto Material's roles, one step up for
  /// Windows displays: Body 14 (macOS uses 13 on Retina screens), Headline
  /// 14 semibold, Title 3 16, Title 2 18, Title 1 24, Large Title 28,
  /// Callout 13, Subheadline 12 and Caption 11. Hierarchy comes from weight
  /// more than size, and no style is smaller than the 10 pt desktop minimum.
  static TextTheme _textTheme(Brightness brightness, ColorScheme scheme) {
    final base = Typography.material2021(
      platform: defaultTargetPlatform,
      colorScheme: scheme,
    );
    final themed = brightness == Brightness.light ? base.black : base.white;
    TextStyle style(
      TextStyle? from,
      double size,
      double lineHeight,
      FontWeight weight, {
      double tracking = 0,
      Color? color,
    }) => (from ?? const TextStyle()).copyWith(
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color ?? scheme.onSurface,
    );

    return themed.copyWith(
      displayLarge: style(themed.displayLarge, 36, 43, FontWeight.w400),
      displayMedium: style(themed.displayMedium, 30, 36, FontWeight.w400),
      displaySmall: style(themed.displaySmall, 28, 34, FontWeight.w400),
      headlineLarge: style(themed.headlineLarge, 28, 34, FontWeight.w600),
      headlineMedium: style(themed.headlineMedium, 24, 30, FontWeight.w600),
      headlineSmall: style(
        themed.headlineSmall,
        21,
        26,
        FontWeight.w600,
        tracking: -0.2,
      ),
      titleLarge: style(
        themed.titleLarge,
        18,
        23,
        FontWeight.w600,
        tracking: -0.2,
      ),
      titleMedium: style(themed.titleMedium, 16, 21, FontWeight.w600),
      titleSmall: style(themed.titleSmall, 14, 18, FontWeight.w600),
      bodyLarge: style(themed.bodyLarge, 14, 20, FontWeight.w400),
      bodyMedium: style(themed.bodyMedium, 14, 19, FontWeight.w400),
      bodySmall: style(
        themed.bodySmall,
        12,
        16,
        FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: style(themed.labelLarge, 14, 18, FontWeight.w500),
      labelMedium: style(themed.labelMedium, 13, 17, FontWeight.w500),
      labelSmall: style(themed.labelSmall, 11, 14, FontWeight.w500),
    );
  }

  static OutlineInputBorder _inputBorder(BorderSide side) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(controlRadius),
    borderSide: side,
  );

  static Color _shadowColor(Brightness brightness) => Colors.black.withValues(
    alpha: brightness == Brightness.light ? 0.25 : 0.6,
  );

  static List<BoxShadow> _shadow(
    Brightness brightness, {
    required double blur,
    required double offset,
  }) => [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: brightness == Brightness.light ? 0.12 : 0.4,
      ),
      blurRadius: blur,
      offset: Offset(0, offset),
    ),
  ];

  /// Hand cursor on enabled buttons (as in 2.x), default arrow when disabled.
  static final WidgetStateProperty<MouseCursor> _clickCursor =
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
      );
}

/// Hover and press overlays drawn over neutral surfaces.
final class _Overlays {
  _Overlays(Color foreground)
    : hover = foreground.withValues(alpha: 0.06),
      pressed = foreground.withValues(alpha: 0.1);

  final Color hover;
  final Color pressed;
}
