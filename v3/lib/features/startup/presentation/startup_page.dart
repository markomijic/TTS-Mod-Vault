import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/app_shell.dart';
import 'package:tts_mod_vault/app/widgets/error_message.dart';
import 'package:tts_mod_vault/app/widgets/progress_message.dart';
import 'package:tts_mod_vault/features/library/application/refresh_progress.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';
import 'package:tts_mod_vault/features/startup/presentation/select_directories_view.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Duration of the cross-fade between startup states.
const Duration _switchDuration = Duration(milliseconds: 250);

/// The app's home: renders the current [StartupState] and becomes the
/// [AppShell] once the library is loaded.
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
      AsyncData(value: StartupLoading()) => const _StartupScaffold(
        key: ValueKey('startup-loading'),
        child: _RefreshProgressView(),
      ),
      AsyncData(value: final StartupNeedsDirectories state) => _StartupScaffold(
        key: const ValueKey('startup-needs-directories'),
        child: SelectDirectoriesView(state: state),
      ),
      AsyncData(value: StartupFailed(error: final error)) => _StartupScaffold(
        key: const ValueKey('startup-failed'),
        child: ErrorMessage(
          error: error,
          onRetry: ref.read(startupControllerProvider.notifier).retry,
        ),
      ),
      AsyncError(error: final error) => _StartupScaffold(
        key: const ValueKey('startup-failed'),
        child: ErrorMessage(
          error: error,
          onRetry: ref.read(startupControllerProvider.notifier).retry,
        ),
      ),
      // AsyncLoading and the explicit StartupChecking state.
      _ => _StartupScaffold(
        key: const ValueKey('startup-checking'),
        child: ProgressMessage(message: l10n.startupChecking),
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

/// [ProgressMessage] bound to the library refresh progress.
class _RefreshProgressView extends ConsumerWidget {
  const _RefreshProgressView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progress = ref.watch(refreshProgressProvider);
    if (progress == null) {
      return ProgressMessage(message: l10n.startupLoading);
    }
    final determinate = progress.total > 0;
    return ProgressMessage(
      message: progress.phase.label(l10n),
      value: determinate ? progress.done / progress.total : null,
      detail: determinate
          ? l10n.progressCount(progress.done, progress.total)
          : null,
    );
  }
}
