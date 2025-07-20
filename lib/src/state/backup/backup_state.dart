enum BackupStatusEnum {
  idle,
  awaitingBackupFolder,
  backingUp,
}

class BackupState {
  final BackupStatusEnum status;
  final int totalCount;
  final int currentCount;

  const BackupState({
    this.status = BackupStatusEnum.idle,
    this.totalCount = 0,
    this.currentCount = 0,
  });

  BackupState copyWith({
    BackupStatusEnum? status,
    int? totalCount,
    int? currentCount,
  }) {
    return BackupState(
      status: status ?? this.status,
      totalCount: totalCount ?? this.totalCount,
      currentCount: currentCount ?? this.currentCount,
    );
  }
}
