/// The Appearance section of the Settings dialog: theme mode, the accent
/// colour swatches (the macOS accent colours) and a custom accent colour as a
/// hex value.
/// Every change is applied to `themeControllerProvider` right away as a
/// live preview; the dialog restores the previous theme on Cancel.
library;

import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/app/theme/theme_presets.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/settings/presentation/settings_widgets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Diameter of an accent swatch.
const double _swatchSize = 24;

/// Width of the hex field.
const double _hexFieldWidth = 140;

final RegExp _hexColor = RegExp(r'^#?([0-9a-fA-F]{6})$');

/// `#RRGGBB` of an ARGB [seed].
String seedToHex(int seed) =>
    '#${(seed & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The ARGB value of a `#RRGGBB` / `RRGGBB` string, or null when malformed.
int? seedFromHex(String text) {
  final match = _hexColor.firstMatch(text.trim());
  if (match == null) return null;
  return 0xFF000000 | int.parse(match.group(1)!, radix: 16);
}

/// Edits the theme through `themeControllerProvider`.
class AppearanceSection extends HookConsumerWidget {
  /// Creates the section.
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);
    final hexController = useTextEditingController(
      text: seedToHex(settings.seedColor),
    );
    final hexValid = useState(true);

    // A preset or swatch changed the seed: show it in the field.
    useEffect(() {
      final hex = seedToHex(settings.seedColor);
      if (seedFromHex(hexController.text) != settings.seedColor) {
        hexController.text = hex;
        hexValid.value = true;
      }
      return null;
    }, [settings.seedColor]);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingAppearanceInfo,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Gaps.h16,
          SettingsSectionTitle(l10n.settingThemeMode),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(l10n.themeModeSystem),
                icon: const Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(l10n.themeModeLight),
                icon: const Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text(l10n.themeModeDark),
                icon: const Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: {settings.mode},
            onSelectionChanged: (selection) =>
                controller.setMode(selection.single),
          ),
          Gaps.h24,
          SettingsSectionTitle(l10n.settingAccentColor),
          Wrap(
            spacing: Insets.md,
            runSpacing: Insets.sm,
            children: [
              for (final preset in ThemePresets.all)
                _Swatch(
                  color: Color(preset.seed),
                  label: preset.label(l10n),
                  selected: settings.presetId == preset.id,
                  onTap: () => controller.applyPreset(preset.id),
                ),
            ],
          ),
          Gaps.h24,
          SettingsSectionTitle(l10n.settingCustomColor),
          SizedBox(
            width: _hexFieldWidth,
            child: TextField(
              key: const Key('settings-seed-hex'),
              controller: hexController,
              decoration: InputDecoration(
                hintText: l10n.settingSeedColorHex,
                prefixIcon: settings.presetId == null
                    ? Padding(
                        padding: const EdgeInsets.all(Insets.sm),
                        child: _ColorDot(color: Color(settings.seedColor)),
                      )
                    : null,
                prefixIconConstraints: const BoxConstraints(),
                errorText: hexValid.value ? null : l10n.settingSeedColorInvalid,
              ),
              onChanged: (text) {
                final seed = seedFromHex(text);
                hexValid.value = seed != null;
                if (seed != null && seed != settings.seedColor) {
                  controller.setSeed(seed);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: const SizedBox.square(dimension: Insets.lg),
    );
  }
}

/// A round accent swatch, as in macOS System Settings: the selected one
/// gets a ring and a white dot.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          child: Container(
            width: _swatchSize + 6,
            height: _swatchSize + 6,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: selected
                  ? const Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(dimension: 8),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
