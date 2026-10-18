import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Blur strength applied behind dialogs, matching 2.x.
const double _backdropBlurSigma = 2;

/// The standard dialog frame: a Material [AlertDialog] with an optional
/// blurred backdrop.
class AppDialog extends StatelessWidget {
  /// Creates a dialog.
  const AppDialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const [],
    this.blur = true,
  });

  /// Optional heading.
  final String? title;

  /// Body of the dialog.
  final Widget content;

  /// Buttons shown at the bottom, in order.
  final List<Widget> actions;

  /// Whether to blur what is behind the dialog.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final dialog = AlertDialog(
      title: title == null ? null : Text(title!),
      content: content,
      actions: actions.isEmpty ? null : actions,
    );
    if (!blur) return dialog;
    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: _backdropBlurSigma,
        sigmaY: _backdropBlurSigma,
      ),
      child: dialog,
    );
  }
}

/// One option offered by [showChoiceDialog].
@immutable
final class DialogChoice<T> {
  /// Creates a choice.
  const DialogChoice({
    required this.label,
    required this.value,
    this.destructive = false,
  });

  /// Button text.
  final String label;

  /// Value returned when the choice is picked.
  final T value;

  /// Styles the button in the error colour.
  final bool destructive;
}

/// Asks the user to confirm an action.
///
/// Returns true when confirmed, false when cancelled or dismissed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AppDialog(
        title: title,
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          _ChoiceButton(
            label: confirmLabel ?? l10n.confirm,
            destructive: destructive,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Offers several [choices]; returns the picked value or null when cancelled.
Future<T?> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required String message,
  required List<DialogChoice<T>> choices,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AppDialog(
        title: title,
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          for (final choice in choices)
            _ChoiceButton(
              label: choice.label,
              destructive: choice.destructive,
              onPressed: () => Navigator.of(context).pop(choice.value),
            ),
        ],
      );
    },
  );
}

/// Asks the user to confirm an action that has one boolean option.
///
/// Returns null when cancelled or dismissed, otherwise the checkbox value at
/// the time Confirm was pressed. [checkboxInfo], when given, is shown as the
/// tooltip of an info icon next to the checkbox. Port of 2.x
/// `showConfirmDialogWithCheckbox`.
Future<bool?> showConfirmDialogWithCheckbox(
  BuildContext context, {
  required String title,
  required String checkboxLabel,
  String? message,
  String? checkboxInfo,
  String? confirmLabel,
  bool initialValue = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      var checked = initialValue;
      return StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: title,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[Text(message), Gaps.h16],
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: checked,
                    onChanged: (value) =>
                        setState(() => checked = value ?? false),
                  ),
                  Gaps.w4,
                  Flexible(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => checked = !checked),
                      child: Text(checkboxLabel),
                    ),
                  ),
                  if (checkboxInfo != null) ...[
                    Gaps.w8,
                    Tooltip(
                      message: checkboxInfo,
                      child: Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            _ChoiceButton(
              label: confirmLabel ?? l10n.confirm,
              destructive: false,
              onPressed: () => Navigator.of(context).pop(checked),
            ),
          ],
        ),
      );
    },
  );
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.destructive,
    required this.onPressed,
  });

  final String label;
  final bool destructive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton(
      onPressed: onPressed,
      style: destructive
          ? FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            )
          : null,
      child: Text(label),
    );
  }
}
