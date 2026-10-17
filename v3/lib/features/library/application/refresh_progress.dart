import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The steps of a library refresh (plan section 4.4), in order.
enum LibraryRefreshPhase {
  /// Listing the Workshop, Saves and Saved Objects folders.
  scanning,

  /// Reading the new and changed mod JSONs.
  parsing,

  /// Listing the asset cache folders (`Mods/Images`, ...).
  indexingFiles,

  /// Listing `.ttsmod` archives and counting the assets of new ones.
  indexingBackups,

  /// Running the summary query and matching backups.
  summarizing;

  /// Human readable name of the phase.
  String label(AppLocalizations l10n) => switch (this) {
    LibraryRefreshPhase.scanning => l10n.refreshPhaseScanning,
    LibraryRefreshPhase.parsing => l10n.refreshPhaseParsing,
    LibraryRefreshPhase.indexingFiles => l10n.refreshPhaseIndexingFiles,
    LibraryRefreshPhase.indexingBackups => l10n.refreshPhaseIndexingBackups,
    LibraryRefreshPhase.summarizing => l10n.refreshPhaseSummarizing,
  };
}

/// Where a running refresh is: the current [phase] and how many of its
/// [total] items are [done]. [total] is 0 when the phase has no countable
/// items (then the indicator is indeterminate).
final class RefreshProgress {
  /// Creates a progress snapshot.
  const RefreshProgress({required this.phase, this.done = 0, this.total = 0});

  /// Current phase.
  final LibraryRefreshPhase phase;

  /// Items finished in this phase.
  final int done;

  /// Items in this phase, or 0 when unknown.
  final int total;

  /// `done / total` clamped to 0..1, or null when [total] is 0.
  double? get fraction =>
      total <= 0 ? null : (done / total).clamp(0, 1).toDouble();

  /// Copy with some fields replaced.
  RefreshProgress copyWith({
    LibraryRefreshPhase? phase,
    int? done,
    int? total,
  }) => RefreshProgress(
    phase: phase ?? this.phase,
    done: done ?? this.done,
    total: total ?? this.total,
  );

  @override
  bool operator ==(Object other) =>
      other is RefreshProgress &&
      other.phase == phase &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(phase, done, total);

  @override
  String toString() => 'RefreshProgress(${phase.name} $done/$total)';
}

/// Owns the [RefreshProgress] of the running refresh; null when idle.
final class RefreshProgressController extends Notifier<RefreshProgress?> {
  @override
  RefreshProgress? build() => null;

  /// Publishes a new snapshot.
  void set(RefreshProgress progress) => state = progress;

  /// Marks the refresh as idle.
  void clear() => state = null;
}

/// The controller behind [refreshProgressProvider]; the library controller
/// writes through it.
final refreshProgressControllerProvider =
    NotifierProvider<RefreshProgressController, RefreshProgress?>(
      RefreshProgressController.new,
    );

/// The progress of the running library refresh, or null when none runs.
final refreshProgressProvider = Provider<RefreshProgress?>(
  (ref) => ref.watch(refreshProgressControllerProvider),
);
