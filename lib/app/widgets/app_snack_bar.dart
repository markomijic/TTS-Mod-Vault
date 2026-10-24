import 'package:material_ui/material_ui.dart';

/// Shows [message] in a snack bar, replacing any snack bar still on screen.
void showAppSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: duration));
}

/// A [MaterialApp.builder] that hosts snack bars above every route.
///
/// The app-wide [ScaffoldMessenger] draws snack bars only in its outermost
/// [Scaffold]. Without this that is the shell's scaffold, which sits inside
/// the navigator, so an open dialog and its barrier cover the snack bar.
/// Wrapping the navigator in a transparent scaffold makes that scaffold the
/// outermost one, so snack bars paint on top of dialogs.
Widget snackBarsAboveRoutes(BuildContext context, Widget? child) => Scaffold(
  backgroundColor: Colors.transparent,
  body: child ?? const SizedBox.shrink(),
);
