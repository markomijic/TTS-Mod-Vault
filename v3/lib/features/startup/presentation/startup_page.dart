import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/app_shell.dart';
import 'package:tts_mod_vault/app/widgets/error_message.dart';
import 'package:tts_mod_vault/app/widgets/progress_message.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';
import 'package:tts_mod_vault/features/startup/presentation/select_directories_view.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Duration of the cross-fade between startup states. Short, so the common
/// Checking -> Ready hand-over is not seen as a flash.
const Duration _switchDuration = Duration(milliseconds: 120);

/// How long the Checking state stays blank before its indicator appears.
/// The folder check normally finishes well inside this window.
const Duration startupCheckingIndicatorDelay = Duration(milliseconds: 400);

/// The app's home: renders the current [StartupState] and becomes the
/// [AppShell] as soon as the folders are known to be valid (the first
/// library refresh runs behind the shell, which shows its own progress).
class StartupPage extends ConsumerWidget {
  /// Creates the page.
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupControllerProvider);
    final l10n = AppLocalizations.of(context);

    final Widget child = switch (startup) {
      AsyncData(value: StartupReady()) => const AppShell(
        key: ValueKey('startup-ready'),
      ),
      AsyncData(value: final StartupNeedsDirectories state) => _StartupScaffold(
        key: const ValueKey('startup-needs-directories'),
        child: SelectDirectoriesView(state: state),
      ),
      AsyncData(value: StartupFailed(error: final error)) ||
      AsyncError(error: final error) => _StartupScaffold(
        key: const ValueKey('startup-failed'),
        child: ErrorMessage(
          error: error,
          onRetry: ref.read(startupControllerProvider.notifier).retry,
        ),
      ),
      // AsyncLoading and the explicit StartupChecking state: an empty page
      // first, the indicator only if the check takes unusually long.
      _ => _StartupScaffold(
        key: const ValueKey('startup-checking'),
        child: _Delayed(
          delay: startupCheckingIndicatorDelay,
          child: ProgressMessage(message: l10n.startupChecking),
        ),
      ),
    };

    return AnimatedSwitcher(duration: _switchDuration, child: child);
  }
}

/// Scaffold used by every non-shell startup state.
class _StartupScaffold extends StatelessWidget {
  const _StartupScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: child)),
  );
}

/// Renders nothing for [delay], then [child]. Keeps a short wait blank
/// instead of flashing an indicator.
class _Delayed extends StatefulWidget {
  const _Delayed({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<_Delayed> {
  Timer? _timer;
  bool _elapsed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _elapsed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _elapsed ? widget.child : const SizedBox.shrink();
}
