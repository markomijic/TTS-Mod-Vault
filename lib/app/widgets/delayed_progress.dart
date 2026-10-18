import 'dart:async' show Timer;

import 'package:flutter_hooks/flutter_hooks.dart'
    show HookWidget, useEffect, useState;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/progress_message.dart';

/// How long the library page waits before showing a loading indicator when
/// it has no data yet: a refresh that finishes sooner never flashes one.
const Duration libraryLoadingIndicatorDelay = Duration(milliseconds: 400);

/// A [ProgressMessage] that stays invisible for [delay] after it is mounted
/// and then appears.
///
/// The delay runs once per mount: changing [message], [value] or [detail]
/// while the widget is visible updates it without hiding it again.
class DelayedProgressMessage extends HookWidget {
  /// Creates the widget.
  const DelayedProgressMessage({
    super.key,
    required this.message,
    this.value,
    this.detail,
    this.delay = libraryLoadingIndicatorDelay,
  });

  /// Main text under the indicator.
  final String message;

  /// Progress fraction in 0..1, or null for an indeterminate indicator.
  final double? value;

  /// Optional secondary line under [message].
  final String? detail;

  /// How long nothing is shown after mounting.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final visible = useState(delay <= Duration.zero);
    useEffect(() {
      if (visible.value) return null;
      final timer = Timer(delay, () => visible.value = true);
      return timer.cancel;
    }, const []);

    if (!visible.value) return const SizedBox.shrink();
    return ProgressMessage(message: message, value: value, detail: detail);
  }
}
