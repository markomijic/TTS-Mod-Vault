/// Typed results of the Workshop operations (replacing v2's string-prefixed
/// messages and exception-text classification).
library;

import 'package:tts_mod_vault/data/net/steam_workshop_client.dart';

export 'package:tts_mod_vault/data/net/steam_workshop_client.dart'
    show WorkshopItemStatus;

/// Outcome of downloading one Workshop item by id.
final class WorkshopDownloadResult {
  /// Creates a result.
  const WorkshopDownloadResult({
    required this.id,
    required this.status,
    this.title,
    this.jsonPath,
    this.error,
    this.cancelled = false,
  });

  /// The Workshop id.
  final String id;

  /// The item's title from Steam, when known.
  final String? title;

  /// Why the item could or could not be downloaded.
  final WorkshopItemStatus status;

  /// Where the mod JSON was written when the download succeeded.
  final String? jsonPath;

  /// Error description when [status] is ok but the download or the file
  /// write failed, or extra detail for the other statuses.
  final String? error;

  /// Whether the operation was cancelled before this item finished.
  final bool cancelled;

  /// Whether the mod JSON was written.
  bool get isSuccess => status.isOk && error == null && !cancelled;

  /// Display name: title when known, else the id.
  String get displayName =>
      title == null || title!.trim().isEmpty ? id : title!;

  @override
  String toString() =>
      'WorkshopDownloadResult($id ${status.name}'
      '${isSuccess ? ' ok' : ''}${cancelled ? ' cancelled' : ''}'
      '${error == null ? '' : ' error=$error'})';
}

/// Every [WorkshopDownloadResult] of one operation with summary counts.
final class WorkshopDownloadBatchResult {
  /// Creates a batch result.
  WorkshopDownloadBatchResult(List<WorkshopDownloadResult> results)
    : results = List.unmodifiable(results);

  /// Results in id order.
  final List<WorkshopDownloadResult> results;

  /// Ids processed.
  int get total => results.length;

  /// Items whose JSON was written.
  int get successCount => results.where((r) => r.isSuccess).length;

  /// Items that failed for any reason other than cancellation.
  int get failedCount =>
      results.where((r) => !r.isSuccess && !r.cancelled).length;

  /// Items not finished because of cancellation.
  int get cancelledCount => results.where((r) => r.cancelled).length;

  /// Whether the operation was cancelled.
  bool get wasCancelled => cancelledCount > 0;

  /// The successful results.
  Iterable<WorkshopDownloadResult> get successful =>
      results.where((r) => r.isSuccess);

  /// The failed results (cancelled ones excluded).
  Iterable<WorkshopDownloadResult> get failed =>
      results.where((r) => !r.isSuccess && !r.cancelled);

  @override
  String toString() =>
      'WorkshopDownloadBatchResult(total=$total ok=$successCount '
      'failed=$failedCount cancelled=$cancelledCount)';
}

/// How updating one Workshop mod ended.
enum WorkshopUpdateStatus {
  /// A newer version was downloaded and written.
  updated,

  /// Steam's version is not newer; nothing was done.
  upToDate,

  /// The details lookup or the download failed; see
  /// `WorkshopUpdateResult.itemStatus` and `error`.
  failed,

  /// The operation was cancelled before this mod finished.
  cancelled,
}

/// Outcome of updating one Workshop mod.
final class WorkshopUpdateResult {
  /// Creates a result.
  const WorkshopUpdateResult({
    required this.id,
    required this.modName,
    required this.jsonPath,
    required this.status,
    this.itemStatus,
    this.error,
  });

  /// The Workshop id (the JSON's basename).
  final String id;

  /// The mod's save name at the time of the update.
  final String modName;

  /// The mod JSON's path.
  final String jsonPath;

  /// How the update ended.
  final WorkshopUpdateStatus status;

  /// Steam's view of the item when [status] is failed.
  final WorkshopItemStatus? itemStatus;

  /// Error description when [status] is failed.
  final String? error;

  @override
  String toString() =>
      'WorkshopUpdateResult($id ${status.name}'
      '${itemStatus == null ? '' : ' ${itemStatus!.name}'}'
      '${error == null ? '' : ' error=$error'})';
}

/// Every [WorkshopUpdateResult] of one operation with summary counts.
final class WorkshopUpdateBatchResult {
  /// Creates a batch result.
  WorkshopUpdateBatchResult(List<WorkshopUpdateResult> results)
    : results = List.unmodifiable(results);

  /// Results in the order the mods were given.
  final List<WorkshopUpdateResult> results;

  /// Mods processed.
  int get total => results.length;

  /// Mods that were updated.
  int get updatedCount => _count(WorkshopUpdateStatus.updated);

  /// Mods already up to date.
  int get upToDateCount => _count(WorkshopUpdateStatus.upToDate);

  /// Mods that failed.
  int get failedCount => _count(WorkshopUpdateStatus.failed);

  /// Mods not finished because of cancellation.
  int get cancelledCount => _count(WorkshopUpdateStatus.cancelled);

  /// Whether the operation was cancelled.
  bool get wasCancelled => cancelledCount > 0;

  int _count(WorkshopUpdateStatus status) =>
      results.where((r) => r.status == status).length;

  @override
  String toString() =>
      'WorkshopUpdateBatchResult(total=$total updated=$updatedCount '
      'upToDate=$upToDateCount failed=$failedCount '
      'cancelled=$cancelledCount)';
}
