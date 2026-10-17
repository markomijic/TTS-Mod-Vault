import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';

/// True while a long-running operation (download, backup, cleanup, ...) is
/// in progress; the sidebar disables its items and the mod cards ignore
/// clicks meanwhile.
///
/// Phase 1: true while a library refresh runs. Later phases OR in the
/// operation runner state.
final operationRunningProvider = Provider<bool>(
  (ref) => ref.watch(libraryControllerProvider.select((s) => s.isLoading)),
);
