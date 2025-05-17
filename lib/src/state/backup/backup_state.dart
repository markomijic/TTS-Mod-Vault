class BackupState {
  final bool importInProgress;
  final bool backupInProgress;
  final String importFileName;

  const BackupState({
    this.importInProgress = false,
    this.backupInProgress = false,
    this.importFileName = "",
  });

  BackupState copyWith({
    bool? importInProgress,
    bool? backupInProgress,
    String? importFileName,
  }) {
    return BackupState(
      importInProgress: importInProgress ?? this.importInProgress,
      backupInProgress: backupInProgress ?? this.backupInProgress,
      importFileName: importFileName ?? this.importFileName,
    );
  }
}
