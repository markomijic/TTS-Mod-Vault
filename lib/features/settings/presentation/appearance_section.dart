/// The Appearance section of the Settings dialog (plan 4.7, 3.0 rollout):
/// theme mode, preset chips and a seed colour (swatches plus a hex field).
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

/// Seed colours offered as swatches (Material 2 500-tones; data, not
/// chrome). The current seed is added when it is none of these.
const List<int> seedColorSwatches = [
  0xFFB3261E,
  0xFFE65100,
  0xFFF9A825,
  0xFF2E7D32,
  0xFF00897B,
  0xFF1565C0,
  0xFF6750A4,
  0xFFC2185B,
  0xFF5D4037,
  0xFF455A64,
];

/// Diameter of a swatch.
const double _swatchSize = 32;

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

    final swatches = [
      ...seedColorSwatches,
      if (!seedColorSwatches.contains(settings.seedColor)) settings.seedColor,
    ];

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
          SettingsSectionTitle(l10n.settingThemePreset),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final preset in ThemePresets.all)
                ChoiceChip(
                  avatar: _ColorDot(color: Color(preset.seed)),
                  label: Text(preset.label(l10n)),
                  selected: settings.presetId == preset.id,
                  onSelected: (_) => controller.applyPreset(preset.id),
                ),
            ],
          ),
          Gaps.h24,
          SettingsSectionTitle(l10n.settingSeedColor),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final seed in swatches)
                _Swatch(
                  seed: seed,
                  selected: seed == settings.seedColor,
                  onTap: () => controller.setSeed(seed),
                ),
            ],
          ),
          Gaps.h12,
          SizedBox(
            width: _hexFieldWidth,
            child: TextField(
              key: const Key('settings-seed-hex'),
              controller: hexController,
              decoration: InputDecoration(
                labelText: l10n.settingSeedColorHex,
                border: const OutlineInputBorder(),
                isDense: true,
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

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.seed,
    required this.selected,
    required this.onTap,
  });

  final int seed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = Color(seed);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? scheme.surface
        : scheme.inverseSurface;
    return Tooltip(
      message: l10n.settingSeedSwatch(seedToHex(seed)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Ink(
          width: _swatchSize,
          height: _swatchSize,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: Insets.lg, color: onColor)
              : null,
        ),
      ),
    );
  }
}
