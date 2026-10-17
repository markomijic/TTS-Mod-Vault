import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';

/// Size of the circular indicator shown above the message.
const double _indicatorSize = 48;

/// A centred circular progress indicator with a message underneath, used
/// for full-page waits (startup, library refresh).
///
/// Replaces 2.x `MessageProgressIndicator`. [value] makes the indicator
/// determinate (0..1); null keeps it spinning. [detail] is an optional
/// second, smaller line such as `12 of 99`.
class ProgressMessage extends StatelessWidget {
  /// Creates the widget.
  const ProgressMessage({
    super.key,
    required this.message,
    this.value,
    this.detail,
  });

  /// Main text under the indicator.
  final String message;

  /// Progress fraction in 0..1, or null for an indeterminate indicator.
  final double? value;

  /// Optional secondary line under [message].
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final detail = this.detail;
    return Padding(
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: _indicatorSize,
            child: CircularProgressIndicator(value: value),
          ),
          Gaps.h16,
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge,
          ),
          if (detail != null) ...[
            Gaps.h8,
            Text(
              detail,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
