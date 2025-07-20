enum BulkActionEnum {
  idle,
  downloadAll,
  backupAll,
  downloadAndBackupAll;
}

class BulkActionsState {
  final BulkActionEnum status;
  final bool cancelledBulkAction;
  final int currentModNumber;
  final int totalModNumber;
  final String statusMessage;

  const BulkActionsState({
    this.status = BulkActionEnum.idle,
    this.cancelledBulkAction = false,
    this.currentModNumber = 0,
    this.totalModNumber = 0,
    this.statusMessage = "",
  });

  BulkActionsState copyWith({
    BulkActionEnum? status,
    bool? cancelledBulkAction,
    int? currentModNumber,
    int? totalModNumber,
    String? statusMessage,
  }) {
    return BulkActionsState(
      status: status ?? this.status,
      cancelledBulkAction: cancelledBulkAction ?? this.cancelledBulkAction,
      currentModNumber: currentModNumber ?? this.currentModNumber,
      totalModNumber: totalModNumber ?? this.totalModNumber,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
