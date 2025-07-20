enum BackupStatusEnum {
  idle,
  awaitingBackupFolder,
  importingBackup,
  backingUp,
}

class BackupState {
  final BackupStatusEnum status;
  final String importFileName;
  final String lastImportedJsonFileName;
  final int totalCount;
  final int currentCount;

  const BackupState({
    this.status = BackupStatusEnum.idle,
    this.importFileName = "",
    this.lastImportedJsonFileName = "",
    this.totalCount = 0,
    this.currentCount = 0,
  });

  BackupState copyWith({
    BackupStatusEnum? status,
    String? importFileName,
    String? lastImportedJsonFileName,
    int? totalCount,
    int? currentCount,
  }) {
    return BackupState(
      status: status ?? this.status,
      importFileName: importFileName ?? this.importFileName,
      lastImportedJsonFileName:
          lastImportedJsonFileName ?? this.lastImportedJsonFileName,
      totalCount: totalCount ?? this.totalCount,
      currentCount: currentCount ?? this.currentCount,
    );
  }
}
