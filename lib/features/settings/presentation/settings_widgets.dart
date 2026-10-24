/// Small building blocks shared by the Settings dialog sections: an info
/// icon with a tooltip, a labelled switch row, a section title, a labelled
/// row and a numeric stepper field.
library;

import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_hooks/flutter_hooks.dart'
    show HookWidget, useEffect, useFocusNode, useTextEditingController;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// How long a settings tooltip stays open once shown.
const Duration _tooltipShowDuration = Duration(seconds: 15);

/// Width of the text field of a [SettingsNumberField].
const double _numberFieldWidth = 72;

/// An info icon that shows [message] on hover.
class SettingsInfoIcon extends StatelessWidget {
  /// Creates the icon.
  const SettingsInfoIcon(this.message, {super.key});

  /// The tooltip text.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: message,
      showDuration: _tooltipShowDuration,
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        height: 1.5,
      ),
      child: Icon(
        Icons.info_outline,
        size: Insets.lg + Insets.xs,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A title line with an optional [SettingsInfoIcon].
class SettingsSectionTitle extends StatelessWidget {
  /// Creates the title.
  const SettingsSectionTitle(this.title, {super.key, this.info});

  /// The text.
  final String title;

  /// Optional tooltip text of an info icon after the title.
  final String? info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (info case final info?) ...[Gaps.w8, SettingsInfoIcon(info)],
        ],
      ),
    );
  }
}

/// A switch row: label, optional info icon, switch.
class SettingsSwitchTile extends StatelessWidget {
  /// Creates the row.
  const SettingsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.info,
  });

  /// The label.
  final String title;

  /// Optional tooltip text of an info icon after the label.
  final String? info;

  /// Current value.
  final bool value;

  /// Called with the new value.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Flexible(child: Text(title)),
          if (info case final info?) ...[Gaps.w8, SettingsInfoIcon(info)],
        ],
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A row with a label (and optional info icon) on the left and [trailing]
/// on the right.
class SettingsLabeledRow extends StatelessWidget {
  /// Creates the row.
  const SettingsLabeledRow({
    super.key,
    required this.title,
    required this.trailing,
    this.info,
  });

  /// The label.
  final String title;

  /// Optional tooltip text of an info icon after the label.
  final String? info;

  /// The control.
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                if (info case final info?) ...[Gaps.w8, SettingsInfoIcon(info)],
              ],
            ),
          ),
          Gaps.w16,
          trailing,
        ],
      ),
    );
  }
}

/// Formats [value] with no decimals when whole and one otherwise.
String formatSettingsNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

/// A minus button, a numeric text field and a plus button bound to a
/// [double] in [min]..[max].
///
/// Typing calls [onChanged] with the parsed value clamped to the range
/// (the text itself is left alone until the field loses focus, so typing
/// "1" on the way to "12" does not snap to [min]). The buttons change the
/// value by [step]. [decimals] allows one decimal place.
class SettingsNumberField extends HookWidget {
  /// Creates the field.
  const SettingsNumberField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.decimals = false,
  });

  /// Current value.
  final double value;

  /// Smallest accepted value.
  final double min;

  /// Largest accepted value.
  final double max;

  /// Amount the buttons add or subtract.
  final double step;

  /// Whether one decimal place may be typed.
  final bool decimals;

  /// Called with the new, clamped value.
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = useTextEditingController(
      text: formatSettingsNumber(value),
    );
    final focusNode = useFocusNode();

    double clamp(double v) => v.clamp(min, max).toDouble();

    void set(double next) {
      final clamped = clamp(next);
      controller.text = formatSettingsNumber(clamped);
      onChanged(clamped);
    }

    useEffect(() {
      void onFocus() {
        if (!focusNode.hasFocus) {
          controller.text = formatSettingsNumber(value);
        }
      }

      focusNode.addListener(onFocus);
      return () => focusNode.removeListener(onFocus);
    }, [focusNode, controller, value]);

    // Keep the text in step with a value changed from outside (reset).
    useEffect(() {
      if (!focusNode.hasFocus) {
        final formatted = formatSettingsNumber(value);
        if (controller.text != formatted) controller.text = formatted;
      }
      return null;
    }, [value]);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: l10n.decrease,
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => set(value - step) : null,
        ),
        SizedBox(
          width: _numberFieldWidth,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(decimal: decimals),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                decimals ? RegExp(r'^\d{0,3}\.?\d?$') : RegExp(r'^\d{0,3}$'),
              ),
            ],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (text) {
              final parsed = double.tryParse(text);
              if (parsed != null) onChanged(clamp(parsed));
            },
            onSubmitted: (_) => set(value),
          ),
        ),
        IconButton(
          tooltip: l10n.increase,
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => set(value + step) : null,
        ),
      ],
    );
  }
}
