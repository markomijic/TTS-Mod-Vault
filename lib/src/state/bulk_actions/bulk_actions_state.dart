enum BulkActionEnum {
  idle,
  downloadAll,
  backupAll,
  downloadAndBackupAll;
}

class BulkActionsState {
  final BulkActionEnum bulkAction;
  final bool bulkActionInProgress;
  final bool cancelledBulkAction;
  final int currentModNumber;
  final int totalModNumber;
  final String statusMessage;

  const BulkActionsState({
    this.bulkAction = BulkActionEnum.idle,
    this.bulkActionInProgress = false,
    this.cancelledBulkAction = false,
    this.currentModNumber = 0,
    this.totalModNumber = 0,
    this.statusMessage = "",
  });

  BulkActionsState copyWith({
    BulkActionEnum? bulkAction,
    bool? bulkActionInProgress,
    bool? cancelledBulkAction,
    int? currentModNumber,
    int? totalModNumber,
    String? statusMessage,
  }) {
    return BulkActionsState(
      bulkAction: bulkAction ?? this.bulkAction,
      bulkActionInProgress: bulkActionInProgress ?? this.bulkActionInProgress,
      cancelledBulkAction: cancelledBulkAction ?? this.cancelledBulkAction,
      currentModNumber: currentModNumber ?? this.currentModNumber,
      totalModNumber: totalModNumber ?? this.totalModNumber,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
