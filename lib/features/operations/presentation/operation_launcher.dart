/// Helpers for widgets that start an operation and show its result.
///
/// The widget that launches an operation is often gone by the time the
/// operation finishes (the selected-mod action buttons are swapped for the
/// progress bar while it runs), so results cannot be shown through the
/// launching widget's `BuildContext`. [OperationUi] captures the navigator
/// and scaffold messenger before the await and shows dialogs and snack
/// bars through them afterwards, the way v2 captured a `NavigatorState`.
library;

import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The UI handles captured from a `BuildContext` before an await.
final class OperationUi {
  /// Captures the root navigator, the scaffold messenger and the
  /// localisations of [context].
  OperationUi.of(BuildContext context)
    : navigator = Navigator.of(context, rootNavigator: true),
      messenger = ScaffoldMessenger.maybeOf(context),
      l10n = AppLocalizations.of(context);

  /// The root navigator; dialogs are pushed on it.
  final NavigatorState navigator;

  /// The messenger snack bars go to (null outside a [Scaffold]).
  final ScaffoldMessengerState? messenger;

  /// Localisations, resolved while the launching widget was mounted.
  final AppLocalizations l10n;

  /// Whether the navigator is still in the tree.
  bool get mounted => navigator.mounted;

  /// A context that outlives the launching widget.
  BuildContext get context => navigator.context;

  /// Shows [message] in a snack bar, replacing the current one.
  void showSnackBar(String message) {
    final messenger = this.messenger;
    if (messenger == null || !messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Shows a dialog on the captured navigator; no-op once it is gone.
  Future<T?> showAppDialog<T>(WidgetBuilder builder) {
    if (!mounted) return Future<T?>.value();
    return showDialog<T>(context: context, builder: builder);
  }

  /// Runs [start] and returns its result, or null when the runner refused
  /// it because another operation is in flight (then the "already running"
  /// snack bar is shown). Other errors propagate.
  Future<T?> launch<T>(Future<T> Function() start) async {
    try {
      return await start();
    } on StateError {
      showSnackBar(l10n.operationAlreadyRunning);
      return null;
    }
  }
}
