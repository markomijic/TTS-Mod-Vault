/// Sidebar "Cleanup" (plan Phase 4, v2 sidebar cleanup flow): scan the
/// asset folders for files no mod uses while a small dismissible modal
/// shows "Scanning…", confirm the deletion in the [CleanupConfirmDialog],
/// delete on the runner and report with a snack bar.
library;

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/features/cleanup/application/cleanup_service.dart';
import 'package:tts_mod_vault/features/cleanup/presentation/cleanup_confirm_dialog.dart';
import 'package:tts_mod_vault/features/cleanup/presentation/cleanup_labels.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Size of the spinner in the scanning modal.
const double _spinnerSize = 24;

/// Runs the cleanup flow. Dismissing the scanning modal cancels the scan
/// (its token) and drops any result it still produces; an empty scan shows
/// "No unused files found" (or the scan's first warning when it failed).
Future<void> runCleanup(BuildContext context, WidgetRef ref) async {
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final service = ref.read(cleanupServiceProvider);

  // The modal pops itself (with true) once the scan answers; the user
  // closing it first pops null, which cancels the scan.
  final token = CancellationToken();
  final scanDone = Completer<void>();
  final modal = ui.showAppDialog<bool>(
    (_) => ScanningDialog(closeWhen: scanDone.future),
  );
  unawaited(
    modal.then((keep) {
      if (keep != true) token.cancel('Scan dismissed');
    }),
  );
  final CleanupScan scan;
  try {
    scan = await service.scanOrphans(token: token);
  } on OperationCancelledException {
    return;
  } finally {
    scanDone.complete();
  }
  final keep = await modal;
  if (keep != true || !ui.mounted) return;

  if (scan.isEmpty) {
    ui.showSnackBar(
      scan.warnings.isEmpty ? l10n.cleanupNothing : scan.warnings.first,
    );
    return;
  }

  final confirmed = await ui.showAppDialog<bool>(
    (_) => CleanupConfirmDialog(scan: scan),
  );
  if (confirmed != true) return;

  final result = await ui.launch(
    () => service.deleteCandidates(scan.candidates),
  );
  if (result == null) return;
  final summary = l10n.cleanupDone(
    result.deleted,
    formatByteSize(l10n, result.bytesFreed),
  );
  ui.showSnackBar(
    result.failed == 0
        ? summary
        : l10n.deleteFailedSuffix(summary, result.failed),
  );
}

/// The "Scanning…" modal: a spinner, the text and a Cancel button (the
/// barrier dismisses it too). Pops with `true` on its own when [closeWhen]
/// completes while it is still open.
class ScanningDialog extends StatefulWidget {
  /// Creates the dialog.
  const ScanningDialog({super.key, required this.closeWhen});

  /// Completes when the scan is done and the dialog should go away.
  final Future<void> closeWhen;

  @override
  State<ScanningDialog> createState() => _ScanningDialogState();
}

class _ScanningDialogState extends State<ScanningDialog> {
  @override
  void initState() {
    super.initState();
    widget.closeWhen.then((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: _spinnerSize,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          Gaps.w16,
          Text(l10n.cleanupScanning),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
