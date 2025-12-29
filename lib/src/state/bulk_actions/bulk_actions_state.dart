enum BulkActionsStatusEnum {
  idle,
  downloadAll,
  backupAll,
  updateUrls,
  downloadAndBackupAll,
  updateModsAll;
}

enum BulkBackupBehaviorEnum {
  skip('Skip'),
  replace('Replace'),
  replaceIfOutOfDate('Replace if out of date');

  final String label;

  const BulkBackupBehaviorEnum(this.label);
}

class BulkActionsState {
  final BulkActionsStatusEnum status;
  final bool cancelledBulkAction;
  final int currentModNumber;
  final int totalModNumber;
  final String statusMessage;

  const BulkActionsState({
    this.status = BulkActionsStatusEnum.idle,
    this.cancelledBulkAction = false,
    this.currentModNumber = 0,
    this.totalModNumber = 0,
    this.statusMessage = "",
  });

  BulkActionsState copyWith({
    BulkActionsStatusEnum? status,
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
