class BackupState {
  final bool importInProgress;
  final bool backupInProgress;
  final String importFileName;
  final String lastImportedJsonFileName;
  final int totalCount;
  final int currentCount;

  const BackupState({
    this.importInProgress = false,
    this.backupInProgress = false,
    this.importFileName = "",
    this.lastImportedJsonFileName = "",
    this.totalCount = 0,
    this.currentCount = 0,
  });

  BackupState copyWith({
    bool? importInProgress,
    bool? backupInProgress,
    String? importFileName,
    String? lastImportedJsonFileName,
    int? totalCount,
    int? currentCount,
  }) {
    return BackupState(
      importInProgress: importInProgress ?? this.importInProgress,
      backupInProgress: backupInProgress ?? this.backupInProgress,
      importFileName: importFileName ?? this.importFileName,
      lastImportedJsonFileName:
          lastImportedJsonFileName ?? this.lastImportedJsonFileName,
      totalCount: totalCount ?? this.totalCount,
      currentCount: currentCount ?? this.currentCount,
    );
  }
}
